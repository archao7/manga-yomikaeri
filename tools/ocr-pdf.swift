#!/usr/bin/env swift
import Foundation
import CoreGraphics
import Vision
import ImageIO
import UniformTypeIdentifiers

// 将每一页渲染为原图 PNG，生成同一卷的 .mokuro 标注供离线点读。针对横排日语。
struct InputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func render(_ page: CGPDFPage) throws -> CGImage {
    let crop = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
    guard !crop.isNull, crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0 else {
        throw InputError("PDF 页面尺寸无效。")
    }
    let rotated = page.rotationAngle % 180 != 0
    let rawWidth = rotated ? crop.height : crop.width
    let rawHeight = rotated ? crop.width : crop.height
    // 普通页面约 144 dpi；限制超大页面的长边，避免分配过大的位图。
    let scale = min(2.0, 3200.0 / max(rawWidth, rawHeight))
    let width = max(1, Int(ceil(rawWidth * scale)))
    let height = max(1, Int(ceil(rawHeight * scale)))
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw InputError("无法渲染 PDF 页面。")
    }
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(canvas)
    context.concatenate(page.getDrawingTransform(.cropBox, rect: canvas, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw InputError("无法生成页面图像。") }
    return image
}

func recognize(_ image: CGImage) throws -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

    let detections = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var rows: [[VNRecognizedTextObservation]] = []
    for observation in detections {
        if let first = rows.last?.first,
           abs(first.boundingBox.midY - observation.boundingBox.midY) <
                min(first.boundingBox.height, observation.boundingBox.height) / 2 {
            rows[rows.count - 1].append(observation)
        } else {
            rows.append([observation])
        }
    }
    let width = Double(image.width), height = Double(image.height)
    // 弧形气泡边框可能被认作单个括号。保留省略号、语气词及带正文的括号。
    let loneBrackets: Set<String> = ["(", ")", "（", "）", "[", "]", "「", "」", "『", "』"]
    return rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }.compactMap { observation in
        guard let value = observation.topCandidates(1).first?.string else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loneBrackets.contains(text) else { return nil }
        let b = observation.boundingBox
        let x1 = max(0, Int(floor(b.minX * width)))
        let x2 = min(image.width, Int(ceil(b.maxX * width)))
        let y1 = max(0, Int(floor((1 - b.maxY) * height)))
        let y2 = min(image.height, Int(ceil((1 - b.minY) * height)))
        guard x1 < x2, y1 < y2 else { return nil }
        return ["box": [x1, y1, x2, y2], "lines": [text], "vertical": false,
                "font_size": y2 - y1, "lines_coords": [[[x1,y1],[x2,y1],[x2,y2],[x1,y2]]]]
    }
}

func exportPage(_ page: CGPDFPage, index: Int, to directory: URL) throws -> [String: Any] {
    let image = try render(page)
    let name = String(format: "page-%04d.png", index)
    let output = directory.appendingPathComponent(name)
    guard let png = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw InputError("无法创建第 \(index) 页 PNG。")
    }
    CGImageDestinationAddImage(png, image, nil)
    guard CGImageDestinationFinalize(png) else { throw InputError("无法保存第 \(index) 页 PNG。") }
    let blocks = try recognize(image)
    print("第 \(index) 页：\(blocks.count) 行" + (blocks.isEmpty ? "（保留原图及空标注）" : ""))
    return ["version": "0.2.0", "img_path": name, "img_width": image.width,
            "img_height": image.height, "blocks": blocks]
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard (1...2).contains(args.count) else { throw InputError("用法：swift 导入漫画PDF.swift 漫画.pdf [新的输出目录]") }
    let source = URL(fileURLWithPath: args[0]).standardizedFileURL
    let title = source.deletingPathExtension().lastPathComponent
    let output = (args.count == 2 ? URL(fileURLWithPath: args[1], isDirectory: true)
                  : source.deletingLastPathComponent().appendingPathComponent(title + "-点读", isDirectory: true)).standardizedFileURL
    let fm = FileManager.default
    guard !fm.fileExists(atPath: output.path) else { throw InputError("输出目录已存在，请指定新目录。") }
    guard let pdf = CGPDFDocument(source as CFURL), pdf.numberOfPages > 0 else {
        throw InputError("无法打开 PDF，请确认文件可读并含有页面。")
    }
    guard pdf.isUnlocked else { throw InputError("此 PDF 有打开密码，请先提供能直接打开的副本。") }

    let stage = output.deletingLastPathComponent().appendingPathComponent(".manga-" + UUID().uuidString)
    try fm.createDirectory(at: stage, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: stage) }
    var pages: [[String: Any]] = []
    for index in 1...pdf.numberOfPages {
        guard let page = pdf.page(at: index) else { throw InputError("缺少第 \(index) 页。") }
        let entry = try autoreleasepool { try exportPage(page, index: index, to: stage) }
        pages.append(entry)
    }
    let volume: [String: Any] = ["version": "0.2.0", "title": title, "volume": title, "pages": pages,
                                  "title_uuid": UUID().uuidString.lowercased(), "volume_uuid": UUID().uuidString.lowercased()]
    let data = try JSONSerialization.data(withJSONObject: volume, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    try data.write(to: stage.appendingPathComponent("volume.mokuro"), options: .atomic)
    try fm.moveItem(at: stage, to: output)
    print("导出 \(pages.count) 页：\(output.path)\n在阅读器选择 volume.mokuro 与需要点读的页面 PNG。")
}
do { try run() } catch {
    FileHandle.standardError.write(Data(("错误：\(error.localizedDescription)\n").utf8))
    exit(1)
}
