import NIO
import NIOExtras
import NIOSSL

public enum SMTPSSLConfiguration {
    case `default`
    case customRoot(path: String)
    case custom(TLSConfiguration)
    
    internal func makeTlsConfiguration() -> TLSConfiguration {
        switch self {
        case .default:
            return TLSConfiguration.clientDefault
        case .customRoot(let path):
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(path)
            return tlsConfig
        case .custom(let config):
            return config
        }
    }
}

public enum SMTPSSLMode {
    case startTLS(configuration: SMTPSSLConfiguration)
    case tls(configuration: SMTPSSLConfiguration)
    case insecure
}

private struct OutstandingRequest {
    let promise: EventLoopPromise<SMTPServerMessage>
    let sendMessage: () -> EventLoopFuture<Void>
}

internal final class ErrorCloseHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    
    init() {}
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }
}

internal final class SMTPClientContext {
    private var queue = [OutstandingRequest]()
    private var isProcessing = false
    let eventLoop: EventLoop
    
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
    
    func sendMessage(
        sendMessage: @escaping () -> EventLoopFuture<Void>
    ) -> EventLoopFuture<SMTPServerMessage> {
        eventLoop.flatSubmit {
            let item = OutstandingRequest(
                promise: self.eventLoop.makePromise(),
                sendMessage: sendMessage
            )
            
            self.queue.append(item)
            
            self.processNext()
            
            return item.promise.futureResult
        }
    }
    
    func receive(_ messages: SMTPServerMessage) {
        self.queue.first?.promise.succeed(messages)
    }
    
    func disconnect() {
        for request in queue {
            request.promise.fail(SMTPError.disconnected)
        }
    }
    
    private func processNext() {
        guard !isProcessing, let item = queue.first else {
            return
        }
        
        isProcessing = true
        item.sendMessage().flatMap {
            item.promise.futureResult
        }.hop(to: eventLoop).whenComplete { _ in
            self.queue.removeFirst()
            self.isProcessing = false
            
            self.processNext()
        }
    }
    
    deinit {
        disconnect()
    }
}

internal struct SMTPHandshake {
    let starttls: Bool
    
    init?(_ message: SMTPServerMessage) {
        guard message.responseCode == .commandOK else {
            return nil
        }
        
        var starttls = false
        
        for line in message.lines {
            let capability = line.uppercased()
            
            if capability == "STARTTLS" {
                starttls = true
            }
        }
        
        self.starttls = starttls
    }
}

public final class SMTPClient {
    private let channel: Channel
    public let eventLoop: EventLoop
    private let context: SMTPClientContext
    public let hostname: String
    public let ssl: SMTPSSLMode
    
    internal private(set) var handshake: SMTPHandshake?
    
    init(
        channel: Channel,
        eventLoop: EventLoop,
        context: SMTPClientContext,
        hostname: String,
        ssl: SMTPSSLMode
    ) {
        self.channel = channel
        self.eventLoop = eventLoop
        self.context = context
        self.hostname = hostname
        self.ssl = ssl
    }
    
    public static func connect(
        hostname: String,
        port: Int,
        ssl: SMTPSSLMode = .startTLS(configuration: .default),
        on eventLoopGroup: EventLoopGroup
    ) -> EventLoopFuture<SMTPClient> {
        let eventLoop = eventLoopGroup.next()
        let context = SMTPClientContext(eventLoop: eventLoop)
        
        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let sslHandler = try? ssl.makeHandler(hostname: hostname, on: channel.eventLoop)
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(SMTPResponseDecoder()),
                    MessageToByteHandler(SMTPRequestEncoder()),
                    ErrorCloseHandler(),
                ]).flatMap {
                    if let sslHandler = sslHandler {
                        return channel.pipeline.addHandler(sslHandler, position: .first)
                    } else {
                        return channel.eventLoop.makeSucceededFuture(())
                    }
                }.flatMap {
                    channel.pipeline.addHandler(SMTPChannelHandler(context: context))
                }
            }
        
        return bootstrap.connect(host: hostname, port: port).flatMap { channel in
            let client = SMTPClient(
                channel: channel,
                eventLoop: eventLoop,
                context: context,
                hostname: hostname,
                ssl: ssl
            )
            
            return client.sendHandshake()
        }
    }
    
    public func sendHandshake() -> EventLoopFuture<SMTPClient> {
        return self.send(EHLOCommand(domainName: self.hostname)).flatMap { message in
            if let handshake = SMTPHandshake(message) {
                self.handshake = handshake
                
                if self.ssl == .startTLS(configuration: .default), handshake.starttls {
                    return self.send(STARTTLSCommand()).flatMap {
                        self.channel.pipeline.removeHandler(try! self.ssl.makeHandler(hostname: self.hostname, on: self.eventLoop))
                    }.flatMap {
                        self.send(EHLOCommand(domainName: self.hostname))
                    }.map { _ in
                        self
                    }
                } else {
                    return self.eventLoop.makeSucceededFuture(self)
                }
            } else {
                return self.eventLoop.makeFailedFuture(SMTPError.invalidHandshake)
            }
        }
    }
    
    public func send(_ command: SMTPClientCommand) -> EventLoopFuture<SMTPServerMessage> {
        return self.context.sendMessage {
            self.channel.writeAndFlush(command)
        }
    }
    
    public func close() -> EventLoopFuture<Void> {
        return self.channel.close()
    }
    
    deinit {
        close()
    }
}
