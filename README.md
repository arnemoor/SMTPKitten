# SMTPKitten

## Create

```swift
let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Welcome to our app!",
    contentType: .plain,
    text: "Welcome to our app, you're all set up & stuff."
)

SMTPClient.connect(
    hostname: "smtp.example.com",
    ssl: .startTLS(configuration: .default)
).flatMap { client in
    client.login(
        user: "noreply@example.com",
        password: "pas$w0rd"
    ).flatMap {
        client.sendMail(mail)
    }
}
```

## Multi-part Support

```swift
let body = MultiPartBody(withParts: [
	MultiPartTextPart(text: "Hello from there!"),
	MultiPartAlternativePart(plainText: "Just a plain text", htmlText: "<h2>Just a HTML</h2>"),
	MultiPartFilePart(mime: "image/jpg",
					  fileName: "Star.jpg",
					  fileBody: "IDEwNiAwIFIKPj4Kc3RhcnR4cmVmCjgwNDkzCiUlRU9GCg=="),	// Base64-encoded file
	MultiPartFilePart(mime: "application/pdf",
					  fileName: "Guide.pdf",
					  fileBody: "IDEwNiAwIFIKPj4Kc3RhcnR4cmVmCjgwNDkzCiUlRU9GCg=="),	// Base64-encoded file
])

let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Some files attached",
	contentType: .init(rawValue: body.contentTypeHeader),
	text: body.string
)

SMTPClient.connect(...)
```
Note you should set the "global" `Content-Type` header and the mail message body to the values provided by `MultiPartBody`.
