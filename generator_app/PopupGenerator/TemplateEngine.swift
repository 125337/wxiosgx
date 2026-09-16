//
//  TemplateEngine.swift
//  模板 dylib 等宽字符串替换引擎
//
//  原理:模板 dylib 内嵌等宽占位符数组(如 TITLE_BEGIN_ + 定长填充),
//  生成时在二进制里定位锚点,按固定宽度写入 UTF-8 内容,多余补 0。
//  因等宽替换不会改变 Mach-O 结构,且模板未签名,替换后即可直接使用。
//
import Foundation

enum GenError: LocalizedError {
    case templateMissing
    case anchorMissing(String)

    var errorDescription: String? {
        switch self {
        case .templateMissing: return "内置模板 dylib 缺失"
        case .anchorMissing(let a): return "模板损坏:找不到占位符 \(a)"
        }
    }
}

struct PopupConfig {
    var title = "发现新版本"
    var message = "有新版本可用，是否前往更新？"
    var confirm = "去更新"
    var cancel = "不再提示"
    var url = ""
    var pluginVersion = ""   // 留空 = 无条件弹
    var showIgnore = true    // 显示"不再提示"按钮
}

struct Placeholder {
    let anchor: String       // 定位锚点
    let width: Int           // 数组总宽度(含锚点)
    var content: String
}

enum TemplateEngine {

    static let placeholders: [Placeholder] = [
        Placeholder(anchor: "TITLE_BEGIN_",    width: 64,   content: ""),
        Placeholder(anchor: "MESSAGE_BEGIN_",  width: 192,  content: ""),
        Placeholder(anchor: "CONFIRM_BEGIN_",  width: 32,   content: ""),
        Placeholder(anchor: "CANCEL_BEGIN_",   width: 32,   content: ""),
        Placeholder(anchor: "URL_BEGIN_",      width: 256,  content: ""),
        Placeholder(anchor: "PLUGINVER_BEGIN_",width: 32,   content: ""),
        Placeholder(anchor: "IGNORE_FLAG_",    width: 20,   content: ""),
    ]

    /// 从 App Bundle 加载模板
    static func loadTemplate() throws -> Data {
        guard let url = Bundle.main.url(forResource: "UpdatePromptTemplate", withExtension: "tpl") else {
            throw GenError.templateMissing
        }
        return try Data(contentsOf: url)
    }

    /// 用配置替换模板占位符,生成新 dylib 二进制
    static func generate(config: PopupConfig, template: Data) throws -> Data {
        var data = template
        var slots = [
            placeholders[0], placeholders[1], placeholders[2],
            placeholders[3], placeholders[4], placeholders[5],
            placeholders[6],
        ]
        slots[0].content = config.title
        slots[1].content = config.message
        slots[2].content = config.confirm
        slots[3].content = config.cancel
        slots[4].content = config.url
        slots[5].content = config.pluginVersion
        slots[6].content = config.showIgnore ? "1" : "0"

        for slot in slots {
            try replace(slot, in: &data)
        }
        return data
    }

    /// 定位锚点并等宽替换(支持 fat binary 内多处出现,全部替换)
    private static func replace(_ slot: Placeholder, in data: inout Data) throws {
        let anchorBytes = Data(slot.anchor.utf8)
        let payloadMax = slot.width - anchorBytes.count - 1   // 留 1 字节 null
        let payload = utf8Padded(slot.content, maxBytes: payloadMax)
        guard payload.count <= payloadMax else {
            throw GenError.anchorMissing(slot.anchor)
        }

        var occurrences = 0
        var searchFrom = 0
        while true {
            guard let range = data.range(of: anchorBytes, in: searchFrom..<data.count) else { break }
            let start = range.lowerBound + anchorBytes.count
            let end = min(start + payloadMax + 1, data.count)
            // 写入 payload + 补 0 至该字段末尾(含末尾 null)
            var block = payload
            while block.count < (payloadMax + 1) { block.append(0) }
            data.replaceSubrange(start..<end, with: block)
            occurrences += 1
            searchFrom = range.lowerBound + slot.width
        }
        if occurrences == 0 {
            throw GenError.anchorMissing(slot.anchor)
        }
    }

    /// UTF-8 编码并按字节截断到 maxBytes(不截断多字节字符)
    private static func utf8Padded(_ s: String, maxBytes: Int) -> Data {
        var bytes = Array(s.utf8)
        if bytes.count > maxBytes {
            bytes = Array(bytes.prefix(maxBytes))
            // 若末尾是不完整 UTF-8 序列,回退到完整字符边界
            while !bytes.isEmpty && (bytes.last! & 0xC0) == 0x80 {
                bytes.removeLast()
            }
            if !bytes.isEmpty && (bytes.last! & 0xC0) == 0xC0 {
                bytes.removeLast()
            }
        }
        return Data(bytes)
    }
}
