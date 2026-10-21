// SPDX-License-Identifier: Apache-2.0
// Reads only OpenType glyph names; outlines and metrics stay in the native font engine.
import Foundation
@_spi(Host) import SwiftOmniUICore

@MainActor struct OpenTypeGlyphNames {
    let names: [String]
    let indices: [String: UInt16]
    init(face: FontFace) {
        let cff = face.table("CFF ")
        let names = cff.isEmpty ? Self.postNames(face.table("post")) : Self.cffNames(cff)
        self.names = names
        self.indices = Dictionary(names.enumerated().filter { $0.offset <= Int(UInt16.max) }.map {
            ($0.element, UInt16($0.offset))
        }, uniquingKeysWith: { first, _ in first })
    }
    private static func u16(_ b: [UInt8], _ at: Int) -> Int? {
        guard at >= 0, at + 1 < b.count else { return nil }; return Int(b[at]) << 8 | Int(b[at + 1])
    }
    private static func u32(_ b: [UInt8], _ at: Int) -> Int? {
        guard let a = u16(b, at), let c = u16(b, at + 2) else { return nil }; return a << 16 | c
    }
    private static func index(_ b: [UInt8], _ cursor: inout Int) -> [[UInt8]]? {
        guard let count = u16(b, cursor) else { return nil }; cursor += 2
        if count == 0 { return [] }
        guard cursor < b.count else { return nil }; let width = Int(b[cursor]); cursor += 1
        guard (1...4).contains(width), cursor + (count + 1) * width <= b.count else { return nil }
        var offsets: [Int] = []
        for _ in 0...count {
            var value = 0
            for _ in 0..<width { value = value << 8 | Int(b[cursor]); cursor += 1 }
            offsets.append(value)
        }
        let start = cursor
        guard offsets.first == 1, let end = offsets.last, end >= 1, start + end - 1 <= b.count else { return nil }
        var objects: [[UInt8]] = []
        for i in 0..<count {
            guard offsets[i] <= offsets[i + 1] else { return nil }
            objects.append(Array(b[(start + offsets[i] - 1)..<(start + offsets[i + 1] - 1)]))
        }
        cursor = start + end - 1
        return objects
    }
    private static func dictionary(_ b: [UInt8]) -> [Int: Int] {
        var result: [Int: Int] = [:], operands: [Int] = [], i = 0
        while i < b.count {
            let n = Int(b[i]); i += 1
            switch n {
            case 32...246: operands.append(n - 139)
            case 247...250:
                guard i < b.count else { return [:] }; operands.append((n - 247) * 256 + Int(b[i]) + 108); i += 1
            case 251...254:
                guard i < b.count else { return [:] }; operands.append(-(n - 251) * 256 - Int(b[i]) - 108); i += 1
            case 28:
                guard let value = u16(b, i) else { return [:] }; operands.append(Int(Int16(bitPattern: UInt16(value)))); i += 2
            case 29:
                guard let value = u32(b, i) else { return [:] }; operands.append(Int(Int32(bitPattern: UInt32(value)))); i += 4
            case 30:
                var done = false
                while i < b.count && !done { done = b[i] & 15 == 15 || b[i] >> 4 == 15; i += 1 }
                operands.append(0) // Real operands belong to unrelated font dictionaries.
            default:
                var key = n
                if n == 12 { guard i < b.count else { return [:] }; key = 1200 + Int(b[i]); i += 1 }
                if let first = operands.first { result[key] = first }
                operands.removeAll(keepingCapacity: true)
            }
        }
        return result
    }
    private static func cffNames(_ b: [UInt8]) -> [String] {
        guard b.count >= 4, b[0] == 1 else { return [] }
        var p = Int(b[2])
        guard index(b, &p) != nil, let top = index(b, &p)?.first,
              let strings = index(b, &p) else { return [] }
        let dict = dictionary(top)
        guard let charStrings = dict[17] else { return [] }
        var cp = charStrings
        guard let glyphs = index(b, &cp) else { return [] }
        let charset = dict[15] ?? 0
        if charset <= 2 {
            let source = charset == 0 ? isoAdobe : charset == 1 ? expert : expertSubset
            return Array(source.prefix(glyphs.count))
        }
        var ids = [0], at = charset
        guard at < b.count else { return [] }; let format = b[at]; at += 1
        while ids.count < glyphs.count {
            guard let first = u16(b, at) else { return [] }; at += 2
            var count = 1
            if format == 1 { guard at < b.count else { return [] }; count += Int(b[at]); at += 1 }
            else if format == 2 { guard let n = u16(b, at) else { return [] }; count += n; at += 2 }
            else if format != 0 { return [] }
            guard count <= glyphs.count - ids.count else { return [] }
            ids.append(contentsOf: first..<(first + count))
        }
        return ids.map { id in
            if id < standard.count { return standard[id] }
            let index = id - standard.count
            return strings.indices.contains(index) ? String(decoding: strings[index], as: UTF8.self) : ".notdef"
        }
    }
    private static func postNames(_ b: [UInt8]) -> [String] {
        guard let version = u32(b, 0) else { return [] }
        if version == 0x10000 { return macintosh }
        guard version == 0x20000, let count = u16(b, 32), 34 + count * 2 <= b.count else { return [] }
        let ids = (0..<count).compactMap { u16(b, 34 + $0 * 2) }
        var custom: [String] = [], cursor = 34 + count * 2
        while cursor < b.count {
            let n = Int(b[cursor]); cursor += 1
            guard cursor + n <= b.count else { return [] }
            custom.append(String(decoding: b[cursor..<(cursor + n)], as: UTF8.self)); cursor += n
        }
        return ids.map { id in
            if id < macintosh.count { return macintosh[id] }
            let index = id - macintosh.count
            return custom.indices.contains(index) ? custom[index] : ".notdef"
        }
    }

    // Standard name lists defined by the Adobe CFF and OpenType post specifications.
    private static let standard = ".notdef space exclam quotedbl numbersign dollar percent ampersand quoteright parenleft parenright asterisk plus comma hyphen period slash zero one two three four five six seven eight nine colon semicolon less equal greater question at A B C D E F G H I J K L M N O P Q R S T U V W X Y Z bracketleft backslash bracketright asciicircum underscore quoteleft a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar braceright asciitilde exclamdown cent sterling fraction yen florin section currency quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright fi fl endash dagger daggerdbl periodcentered paragraph bullet quotesinglbase quotedblbase quotedblright guillemotright ellipsis perthousand questiondown grave acute circumflex tilde macron breve dotaccent dieresis ring cedilla hungarumlaut ogonek caron emdash AE ordfeminine Lslash Oslash OE ordmasculine ae dotlessi lslash oslash oe germandbls onesuperior logicalnot mu trademark Eth onehalf plusminus Thorn onequarter divide brokenbar degree thorn threequarters twosuperior registered minus eth multiply threesuperior copyright Aacute Acircumflex Adieresis Agrave Aring Atilde Ccedilla Eacute Ecircumflex Edieresis Egrave Iacute Icircumflex Idieresis Igrave Ntilde Oacute Ocircumflex Odieresis Ograve Otilde Scaron Uacute Ucircumflex Udieresis Ugrave Yacute Ydieresis Zcaron aacute acircumflex adieresis agrave aring atilde ccedilla eacute ecircumflex edieresis egrave iacute icircumflex idieresis igrave ntilde oacute ocircumflex odieresis ograve otilde scaron uacute ucircumflex udieresis ugrave yacute ydieresis zcaron exclamsmall Hungarumlautsmall dollaroldstyle dollarsuperior ampersandsmall Acutesmall parenleftsuperior parenrightsuperior twodotenleader onedotenleader zerooldstyle oneoldstyle twooldstyle threeoldstyle fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle nineoldstyle commasuperior threequartersemdash periodsuperior questionsmall asuperior bsuperior centsuperior dsuperior esuperior isuperior lsuperior msuperior nsuperior osuperior rsuperior ssuperior tsuperior ff ffi ffl parenleftinferior parenrightinferior Circumflexsmall hyphensuperior Gravesmall Asmall Bsmall Csmall Dsmall Esmall Fsmall Gsmall Hsmall Ismall Jsmall Ksmall Lsmall Msmall Nsmall Osmall Psmall Qsmall Rsmall Ssmall Tsmall Usmall Vsmall Wsmall Xsmall Ysmall Zsmall colonmonetary onefitted rupiah Tildesmall exclamdownsmall centoldstyle Lslashsmall Scaronsmall Zcaronsmall Dieresissmall Brevesmall Caronsmall Dotaccentsmall Macronsmall figuredash hypheninferior Ogoneksmall Ringsmall Cedillasmall questiondownsmall oneeighth threeeighths fiveeighths seveneighths onethird twothirds zerosuperior foursuperior fivesuperior sixsuperior sevensuperior eightsuperior ninesuperior zeroinferior oneinferior twoinferior threeinferior fourinferior fiveinferior sixinferior seveninferior eightinferior nineinferior centinferior dollarinferior periodinferior commainferior Agravesmall Aacutesmall Acircumflexsmall Atildesmall Adieresissmall Aringsmall AEsmall Ccedillasmall Egravesmall Eacutesmall Ecircumflexsmall Edieresissmall Igravesmall Iacutesmall Icircumflexsmall Idieresissmall Ethsmall Ntildesmall Ogravesmall Oacutesmall Ocircumflexsmall Otildesmall Odieresissmall OEsmall Oslashsmall Ugravesmall Uacutesmall Ucircumflexsmall Udieresissmall Yacutesmall Thornsmall Ydieresissmall 001.000 001.001 001.002 001.003 Black Bold Book Light Medium Regular Roman Semibold".split(separator: " ").map(String.init)
    private static let isoAdobe = ".notdef space exclam quotedbl numbersign dollar percent ampersand quoteright parenleft parenright asterisk plus comma hyphen period slash zero one two three four five six seven eight nine colon semicolon less equal greater question at A B C D E F G H I J K L M N O P Q R S T U V W X Y Z bracketleft backslash bracketright asciicircum underscore quoteleft a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar braceright asciitilde exclamdown cent sterling fraction yen florin section currency quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright fi fl endash dagger daggerdbl periodcentered paragraph bullet quotesinglbase quotedblbase quotedblright guillemotright ellipsis perthousand questiondown grave acute circumflex tilde macron breve dotaccent dieresis ring cedilla hungarumlaut ogonek caron emdash AE ordfeminine Lslash Oslash OE ordmasculine ae dotlessi lslash oslash oe germandbls onesuperior logicalnot mu trademark Eth onehalf plusminus Thorn onequarter divide brokenbar degree thorn threequarters twosuperior registered minus eth multiply threesuperior copyright Aacute Acircumflex Adieresis Agrave Aring Atilde Ccedilla Eacute Ecircumflex Edieresis Egrave Iacute Icircumflex Idieresis Igrave Ntilde Oacute Ocircumflex Odieresis Ograve Otilde Scaron Uacute Ucircumflex Udieresis Ugrave Yacute Ydieresis Zcaron aacute acircumflex adieresis agrave aring atilde ccedilla eacute ecircumflex edieresis egrave iacute icircumflex idieresis igrave ntilde oacute ocircumflex odieresis ograve otilde scaron uacute ucircumflex udieresis ugrave yacute ydieresis zcaron".split(separator: " ").map(String.init)
    private static let expert = ".notdef space exclamsmall Hungarumlautsmall dollaroldstyle dollarsuperior ampersandsmall Acutesmall parenleftsuperior parenrightsuperior twodotenleader onedotenleader comma hyphen period fraction zerooldstyle oneoldstyle twooldstyle threeoldstyle fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle nineoldstyle colon semicolon commasuperior threequartersemdash periodsuperior questionsmall asuperior bsuperior centsuperior dsuperior esuperior isuperior lsuperior msuperior nsuperior osuperior rsuperior ssuperior tsuperior ff fi fl ffi ffl parenleftinferior parenrightinferior Circumflexsmall hyphensuperior Gravesmall Asmall Bsmall Csmall Dsmall Esmall Fsmall Gsmall Hsmall Ismall Jsmall Ksmall Lsmall Msmall Nsmall Osmall Psmall Qsmall Rsmall Ssmall Tsmall Usmall Vsmall Wsmall Xsmall Ysmall Zsmall colonmonetary onefitted rupiah Tildesmall exclamdownsmall centoldstyle Lslashsmall Scaronsmall Zcaronsmall Dieresissmall Brevesmall Caronsmall Dotaccentsmall Macronsmall figuredash hypheninferior Ogoneksmall Ringsmall Cedillasmall onequarter onehalf threequarters questiondownsmall oneeighth threeeighths fiveeighths seveneighths onethird twothirds zerosuperior onesuperior twosuperior threesuperior foursuperior fivesuperior sixsuperior sevensuperior eightsuperior ninesuperior zeroinferior oneinferior twoinferior threeinferior fourinferior fiveinferior sixinferior seveninferior eightinferior nineinferior centinferior dollarinferior periodinferior commainferior Agravesmall Aacutesmall Acircumflexsmall Atildesmall Adieresissmall Aringsmall AEsmall Ccedillasmall Egravesmall Eacutesmall Ecircumflexsmall Edieresissmall Igravesmall Iacutesmall Icircumflexsmall Idieresissmall Ethsmall Ntildesmall Ogravesmall Oacutesmall Ocircumflexsmall Otildesmall Odieresissmall OEsmall Oslashsmall Ugravesmall Uacutesmall Ucircumflexsmall Udieresissmall Yacutesmall Thornsmall Ydieresissmall".split(separator: " ").map(String.init)
    private static let expertSubset = ".notdef space dollaroldstyle dollarsuperior parenleftsuperior parenrightsuperior twodotenleader onedotenleader comma hyphen period fraction zerooldstyle oneoldstyle twooldstyle threeoldstyle fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle nineoldstyle colon semicolon commasuperior threequartersemdash periodsuperior asuperior bsuperior centsuperior dsuperior esuperior isuperior lsuperior msuperior nsuperior osuperior rsuperior ssuperior tsuperior ff fi fl ffi ffl parenleftinferior parenrightinferior hyphensuperior colonmonetary onefitted rupiah centoldstyle figuredash hypheninferior onequarter onehalf threequarters oneeighth threeeighths fiveeighths seveneighths onethird twothirds zerosuperior onesuperior twosuperior threesuperior foursuperior fivesuperior sixsuperior sevensuperior eightsuperior ninesuperior zeroinferior oneinferior twoinferior threeinferior fourinferior fiveinferior sixinferior seveninferior eightinferior nineinferior centinferior dollarinferior periodinferior commainferior".split(separator: " ").map(String.init)
    private static let macintosh = ".notdef .null nonmarkingreturn space exclam quotedbl numbersign dollar percent ampersand quotesingle parenleft parenright asterisk plus comma hyphen period slash zero one two three four five six seven eight nine colon semicolon less equal greater question at A B C D E F G H I J K L M N O P Q R S T U V W X Y Z bracketleft backslash bracketright asciicircum underscore grave a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar braceright asciitilde Adieresis Aring Ccedilla Eacute Ntilde Odieresis Udieresis aacute agrave acircumflex adieresis atilde aring ccedilla eacute egrave ecircumflex edieresis iacute igrave icircumflex idieresis ntilde oacute ograve ocircumflex odieresis otilde uacute ugrave ucircumflex udieresis dagger degree cent sterling section bullet paragraph germandbls registered copyright trademark acute dieresis notequal AE Oslash infinity plusminus lessequal greaterequal yen mu partialdiff summation product pi integral ordfeminine ordmasculine Omega ae oslash questiondown exclamdown logicalnot radical florin approxequal Delta guillemotleft guillemotright ellipsis nonbreakingspace Agrave Atilde Otilde OE oe endash emdash quotedblleft quotedblright quoteleft quoteright divide lozenge ydieresis Ydieresis fraction currency guilsinglleft guilsinglright fi fl daggerdbl periodcentered quotesinglbase quotedblbase perthousand Acircumflex Ecircumflex Aacute Edieresis Egrave Iacute Icircumflex Idieresis Igrave Oacute Ocircumflex apple Ograve Uacute Ucircumflex Ugrave dotlessi circumflex tilde macron breve dotaccent ring cedilla hungarumlaut ogonek caron Lslash lslash Scaron scaron Zcaron zcaron brokenbar Eth eth Yacute yacute Thorn thorn minus multiply onesuperior twosuperior threesuperior onehalf onequarter threequarters franc Gbreve gbreve Idotaccent Scedilla scedilla Cacute cacute Ccaron ccaron dcroat".split(separator: " ").map(String.init)
}
