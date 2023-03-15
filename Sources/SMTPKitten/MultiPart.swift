//
//  MultiPart.swift
//  SMTPKitten
//
//  Created by Alex Sherbakov on 15-03-23.
//  Copyright © 2023 Alex Sherbakov. All rights reserved.
//

import Foundation
import NIO

protocol MultiPartProtocol {
	var lines: [String] { get set }
}

final class MultiPartTextPart: MultiPartProtocol {
	
	var lines: [String] = []
	
	init(text: String) {
		let headers = """
		Content-Transfer-Encoding: 8BIT
		Content-Type: text/plain; charset=utf-8
		Mime-Version: 1.0
		"""
		lines.append(headers)
		lines.append("")
		lines.append(text)
	}
}

final class MultiPartFilePart: MultiPartProtocol {
	
	var lines: [String] = []
	
	init(mime: String, fileName: String, fileBody: String) {
		let headers = """
		Content-Transfer-Encoding: base64
		Content-Type: \(mime); name="\(fileName)"
		Content-Disposition: attachment; filename="\(fileName)"
		"""
		lines.append(headers)
		lines.append("")
		lines.append(fileBody)
	}
}

final class MultiPartAlternativePart: MultiPartProtocol {
	
	private let alternativeBoundary: String = UUID().uuidString
	private lazy var alternativeHeader = "Content-Type: multipart/alternative; boundary=\(alternativeBoundary)"
	
	var lines: [String] = []
	
	init(plainText: String, htmlText: String) {
		let textHeaders = """
		Content-Transfer-Encoding: 8BIT
		Content-Type: text/plain; charset=utf-8
		Mime-Version: 1.0
		"""
		let htmlHeaders = """
		Content-Transfer-Encoding: 8BIT
		Content-Type: text/html; charset=utf-8
		Mime-Version: 1.0
		"""
		lines.append(alternativeHeader)
		lines.append("")
		lines.append("--\(alternativeBoundary)")
		lines.append(textHeaders)
		lines.append("")
		lines.append(plainText)
		lines.append("--\(alternativeBoundary)")
		lines.append(htmlHeaders)
		lines.append("")
		lines.append(htmlText)
		lines.append("")
		lines.append("--\(alternativeBoundary)--")
		lines.append("")
	}
}

final class MultiPartBody {
	
	private let multipartBoundary = UUID().uuidString
	private(set) var lines: [String] = []
	
	public lazy var contentTypeHeader = "multipart/mixed; boundary=\(multipartBoundary)"
	
	public var string: String { lines.joined(separator: "\n") }
	public var data: Data { Data(string.utf8) }
	
	init(withParts parts: [MultiPartProtocol] = []) {
		parts.forEach {
			lines.append("--\(multipartBoundary)")
			lines.append(contentsOf: $0.lines)
		}
		
		lines.append("--\(multipartBoundary)--")
	}
}
