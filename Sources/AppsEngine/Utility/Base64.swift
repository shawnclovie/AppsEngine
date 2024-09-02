//
//  Base64.swift
//  
//
//  Created by Shawn Clovie on 2023/4/1.
//

import Foundation

/// A radix 64 encoding/decoding scheme, defined by a 64-character alphabet.
///
/// The most common encoding is the "base64" encoding defined in
/// RFC 4648 and used in MIME (RFC 2045) and PEM (RFC 1421).
///
/// RFC 4648 also defines an alternate encoding, which is
/// the standard encoding with - and _ substituted for + and /.
public struct Base64Encoding : Sendable{
	/// Standard base64 encoding, as defined in RFC 4648.
	public static let standard = Self(urlSafe: false, pad: true)

	/// Alternate base64 encoding defined in RFC 4648.
	public static let urlSafeNoPad = Self(urlSafe: true, pad: false)

	private static let standardDigits = [UInt8]("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
	private static let urlSafeDigits = [UInt8]("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

	static func digits(urlSafe: Bool) -> [UInt8] {
		urlSafe ? urlSafeDigits : standardDigits
	}

	private static let padCharacter = Character("=").asciiValue!

	/// count: 64
	private let urlSafe: Bool
	/// count: 256
	private let decodeMap: [UInt8]
	private let pad: Bool

	private init(urlSafe: Bool, pad: Bool) {
		self.urlSafe = urlSafe
		self.pad = pad

		let digits = Self.digits(urlSafe: urlSafe)
		var decMap = [UInt8](repeating: 0xFF, count: 255)
		for (i, ch) in digits.enumerated() {
			decMap[Int(ch)] = UInt8(i)
		}
		decodeMap = decMap
	}

	var digits: [UInt8] {
		Self.digits(urlSafe: urlSafe)
	}

	public func encodeToString(_ src: Data) -> String {
		String(decoding: encode(src), as: UTF8.self)
	}

	/// Encodes `src` using the encoding.
	///
	/// The encoding pads the output to a multiple of 4 bytes,
	/// so `encode` is not appropriate for use on individual blocks
	/// of a large data stream.
	public func encode(_ src: Data) -> Data {
		if urlSafe && !pad {
			return encodeForURLSafeNoPad(src)
		}
		return src.base64EncodedData()
	}

	func encodeForURLSafeNoPad(_ src: Data) -> Data {
		let count = src.count
		guard count > 0 else {
			return Data()
		}
		// the would-be amount of padding, for calculations
		let padding = (3 - (count % 3)) % 3
		let encodedLength = 4 * ((count + padding) / 3)
		let digits = self.digits

		var encoded = Data(count: encodedLength - padding)
		var outputIndex = 0

		var inputIndex = 0
		// 3 bytes of data -> 4 characters encoded
		while inputIndex + 3 <= count {
			let byte1 = Int(src[inputIndex])
			let byte2 = Int(src[inputIndex + 1])
			let byte3 = Int(src[inputIndex + 2])
			inputIndex += 3
			encoded[outputIndex]     = digits[byte1 >> 2]
			encoded[outputIndex + 1] = digits[((byte1 & 0x03) << 4) | (byte2 >> 4)]
			encoded[outputIndex + 2] = digits[((byte2 & 0x0F) << 2) | (byte3 >> 6)]
			encoded[outputIndex + 3] = digits[byte3 & 0x3F]
			outputIndex += 4
		}
		// byte count was not divisible by 3
		if padding != 0 {
			let byte1 = Int(src[inputIndex])
			let byte2 = (padding == 1) ? Int(src[inputIndex + 1]) : 0

			encoded[outputIndex]     = digits[byte1 >> 2]
			encoded[outputIndex + 1] = digits[((byte1 & 0x03) << 4) | (byte2 >> 4)]
			if padding == 1 {
				encoded[outputIndex + 2] = digits[(byte2 & 0x0F) << 2]
			}
		}
		return encoded
	}

	public func decode(_ input: String, options: Data.Base64DecodingOptions = []) -> Data? {
		decode(Data(input.utf8), options: options)
	}

	/// Decodes `src` using the encoding.
	/// It writes at most `decodedLength(src.count)` bytes to result
	/// and returns the number of bytes written.
	///
	/// If src contains invalid base64 data, it will return the
	/// number of bytes successfully written and CorruptInputError.
	/// New line characters (\r and \n) are ignored.
	public func decode(_ input: Data, options: Data.Base64DecodingOptions = []) -> Data? {
		if !urlSafe && pad {
			guard let dst = Data(base64Encoded: input, options: options) else {
				return nil
			}
			return dst
		}
		return decode(urlSafeNoPad: input, options: options)
	}

	private func decode(urlSafeNoPad input: Data, options: Data.Base64DecodingOptions = []) -> Data? {
		let encoded = options.contains(.ignoreUnknownCharacters) && !input.isEmpty
		? input.filter({ byte in
			decodeMap[Int(byte)] != 64
		})
		: input
		let count = encoded.count
		guard count != 0 else {
			return Data()
		}

		let trailingEncoded = count % 4
		let trailingBytes = trailingEncoded == 0 ? 0 : trailingEncoded - 1
		let decodedLength = (count / 4) * 3 + trailingBytes
		var dst = Data(count: decodedLength)

		var i = 0
		var outputIndex = 0
		var errorCheck = 0

		let decodeNextByte: () -> Int = {
			let byte = Int(decodeMap[Int(encoded[i])])
			i += 1
			errorCheck |= byte
			return byte
		}
		// decode 4 characters to 3 bytes
		while i + 4 <= count {
			var value = decodeNextByte() << 18
			value |= decodeNextByte() << 12
			value |= decodeNextByte() << 6
			value |= decodeNextByte()

			dst[outputIndex] = UInt8(truncatingIfNeeded: value >> 16)
			outputIndex += 1
			dst[outputIndex] = UInt8(truncatingIfNeeded: value >> 8)
			outputIndex += 1
			dst[outputIndex] = UInt8(truncatingIfNeeded: value)
			outputIndex += 1
		}
		// decode the last 2 or 3 characters
		if trailingBytes != 0 {
			var value = decodeNextByte() << 12
			value |= decodeNextByte() << 6

			dst[outputIndex] = UInt8(truncatingIfNeeded: value >> 10)
			if trailingBytes != 1 {
				outputIndex += 1
				value |= decodeNextByte()
				dst[outputIndex] = UInt8(truncatingIfNeeded: value >> 2)
			}
		}

		guard errorCheck & 0xC0 == 0 else {
			return nil
		}
		return dst
	}
}
