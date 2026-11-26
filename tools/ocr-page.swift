#!/usr/bin/env swift
import Foundation
import Vision
import ImageIO

// 单页横排日语 OCR，以 .mokuro 页结构保存文本和像素位置。需要 macOS 与 Swift。
// 用法：swift 识别漫画页.swift 漫画.png [漫画.mokuro]
struct InputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard (1...2).contains(args.count) else {
        throw InputError("用法：swift 识别漫画页.swift 漫画图片 [输出.mokuro]")
    }
    let imageURL = URL(fileURLWithPath: args[0]).standardizedFileURL
    let outputURL = args.count == 2 ? URL(fileURLWithPath: args[1]).standardizedFileURL :
        imageURL.deletingPathExtension().appendingPathExtension("mokuro")
    guard outputURL.pathExtension.lowercased() == "mokuro", outputURL != imageURL else {
        throw InputError("输出必须是独立的 .mokuro 文件。")
    }
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw InputError("无法读取图像，请检查路径及文件格式。")
    }
    let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = CGImagePropertyOrientation(rawValue: metadata?[kCGImagePropertyOrientation] as? UInt32 ?? 1) ?? .up
    let swapAxes = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
    let width = swapAxes ? image.height : image.width
    let height = swapAxes ? image.width : image.height
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

    // 横排阅读顺序：从上至下扫描行中心，处于同一行高容差的各块从左到右排序。
    // 文字行按观测位置排列，不推断分镜边界。
    let detections = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var rows: [[VNRecognizedTextObservation]] = []
    for observation in detections {
        if let first = rows.last?.first,
           abs(first.boundingBox.midY - observation.boundingBox.midY) < min(first.boundingBox.height, observation.boundingBox.height) / 2 {
            rows[rows.count-1].append(observation)
        } else {
            rows.append([observation])
        }
    }
    let readingOrder = rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    // 坐标原点转为左上。每个观测项是一行。
    var blocks: [[String:Any]] = []
    for observation in readingOrder {
        guard let value = observation.topCandidates(1).first?.string, !value.isEmpty else { continue }
        let b = observation.boundingBox
        let x1 = max(0, Int(floor(b.minX * Double(width))))
        let x2 = min(width, Int(ceil(b.maxX * Double(width))))
        let y1 = max(0, Int(floor((1-b.maxY) * Double(height))))
        let y2 = min(height, Int(ceil((1-b.minY) * Double(height))))
        guard x2 > x1, y2 > y1 else { continue }
        blocks.append(["box":[x1,y1,x2,y2], "lines":[value], "vertical":false,
                       "font_size":y2-y1, "lines_coords":[[[x1,y1],[x2,y1],[x2,y2],[x1,y2]]]])
    }
    guard !blocks.isEmpty else { throw InputError("未识别到文字，请尝试更清楚的横排日语图像。") }
    let page: [String:Any] = ["version":"0.2.0", "img_path":imageURL.lastPathComponent,
                              "img_width":width, "img_height":height, "blocks":blocks]
    let title = imageURL.deletingPathExtension().lastPathComponent
    var doc: [String:Any] = ["version":"0.2.0", "title":title, "volume":title, "pages":[page],
                             "title_uuid":UUID().uuidString.lowercased(), "volume_uuid":UUID().uuidString.lowercased()]
    if FileManager.default.fileExists(atPath: outputURL.path) {
        // 保留同一输入的读者标识，以便再次识别后仍能读到已保存的校正。
        guard let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: outputURL)) as? [String:Any],
              let pages = existing["pages"] as? [[String:Any]], pages.count == 1,
              pages[0]["img_path"] as? String == imageURL.lastPathComponent,
              pages[0]["img_width"] as? Int == width, pages[0]["img_height"] as? Int == height else {
            throw InputError("已有输出不匹配这张图片，请指定新的 .mokuro 文件名。")
        }
        for key in ["title_uuid", "volume_uuid"] {
            if let id = existing[key] as? String { doc[key] = id }
        }
    }
    let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
    try data.write(to: outputURL, options: .atomic)
    print("已识别 \(blocks.count) 行：\(outputURL.path)")
}
do { try run() } catch {
    FileHandle.standardError.write(Data(("错误：\(error.localizedDescription)\n").utf8))
    exit(1)
}
