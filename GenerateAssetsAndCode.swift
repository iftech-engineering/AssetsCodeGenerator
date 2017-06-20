//
//  GenerateAssetsAndCode.swift
//  ImageAssetsTool
//
//  Created by Jason Yu on 6/14/17.
//  Copyright © 2017 Jike. All rights reserved.
//

import Foundation

let redPrefix = "\u{001B}[0;31m"
let greenPrefix = "\u{001B}[0;32m"

var inputImagesPathArg: String?
var outputAssetsPathArg: String?
var outputCodePathArg: String?

let templatesPath = "."

func invalidParameters() {
    print("!!!Error: Invalid parameters")
    exit(1)
}

let args = CommandLine.arguments
var i = 0
func checkParamBound(_ i: Int) {
    if i >= args.count {
        invalidParameters()
    }
}

while i < args.count {
    let arg = args[i]
    
    switch arg {
    case "-i":
        i += 1
        checkParamBound(i)
        inputImagesPathArg = args[i]
        print("inputImagesPath: \(args[i])")
    case "-assetsOutput":
        i += 1
        checkParamBound(i)
        outputAssetsPathArg = args[i]
        print("outputAssetsPathArg: \(args[i])")
    case "-codeOutput":
        i += 1
        checkParamBound(i)
        outputCodePathArg = args[i]
        print("outputCodePathArg: \(args[i])")
    default: break
    }
    i += 1
}

guard let inputImagesPath = inputImagesPathArg,
    let outputAssetsPath = outputAssetsPathArg,
    let outputCodePath = outputCodePathArg else {
        invalidParameters()
        exit(1)
}

let fileManager = FileManager.default

let templateJsonData = try! Data(contentsOf: URL(fileURLWithPath: "ContentsTemplate.json"))
let contentsTemplateJson = try! JSONSerialization.jsonObject(with: templateJsonData, options: .allowFragments)

var allImageNames: Set<String> = []

var errorItems: [(path: String, reason: String)] = []

class Regex {
    let regex: String
    init(_ regex: String) {
        self.regex = regex
    }
    
    func test(_ testString: String) -> Bool {
        return testString.range(of: regex, options: .regularExpression) != nil
    }
}

let supportedImageTypes: Set<String> = ["png", "jpg"]

func validateImageFileName(fileName: String) -> Bool {
    return Regex("^[A-Z0-9a-z_]+@(2x|3x)\\.(\(supportedImageTypes.joined(separator: "|")))$").test(fileName)
}

func copyImageToOutput(sourcePath: String) {
    let sourceUrl = URL(fileURLWithPath: sourcePath)
    
    let fileNameWithExt = sourceUrl.lastPathComponent
    guard validateImageFileName(fileName: fileNameWithExt) else {
        errorItems.append((sourcePath, "Invalid file name"))
        return
    }
    
    // additional check: if @2x file exists, make sure @3x also exists
    if Regex("@2x\\.(\(supportedImageTypes.joined(separator: "|"))$").test(sourcePath) {
        let threeXPath = sourcePath.replacingOccurrences(of: "@2x", with: "@3x")
        guard fileManager.fileExists(atPath: threeXPath) else {
            errorItems.append((sourcePath, "@2x image exists but @3x is missing"))
            return
        }
    }
    
    let iconName = fileNameWithExt.substring(to: fileNameWithExt.index(fileNameWithExt.endIndex, offsetBy: -7))
    print("=== Processing icon: \(iconName) ===")
    allImageNames.insert(iconName)
    
    do {
        
        // create target directory if needed
        let targetDirectoryPath = "\(outputAssetsPath)/\(iconName).imageset"
        try fileManager.createDirectory(atPath: targetDirectoryPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions.rawValue: 0o766])
        
        // create contents.json if needed
        let contentsJsonPath = "\(targetDirectoryPath)/Contents.json"
        if fileManager.fileExists(atPath: contentsJsonPath) == false {
            print("Contents.json doesn't exist. Creating json file")
            fileManager.createFile(atPath: contentsJsonPath, contents: templateJsonData, attributes: [FileAttributeKey.posixPermissions.rawValue: 0o766])
        }
        
        // modify json and write to file
        let existingJson = getJson(at: contentsJsonPath)
        let json = addImageToContentsJson(imageFileName: fileNameWithExt, json: existingJson)
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        print("Saving \(fileNameWithExt) to contents.json")

        try jsonData.write(to: URL(fileURLWithPath: contentsJsonPath))
        
        // copy image to target directory
        let sourceImagePath = "\(inputImagesPath)/\(sourcePath)"
        let targetImagePath = "\(targetDirectoryPath)/\(fileNameWithExt)"
        print("copy from \(sourceImagePath) to \(targetImagePath)")
        try fileManager.copyItem(atPath: sourceImagePath, toPath: targetImagePath)
    } catch {
        print("!!! Error \(error)")
        errorItems.append((sourcePath, "\(error)"))
    }
}

func addImageToContentsJson(imageFileName: String, json: Any) -> Any {
    let beginIndex = imageFileName.index(imageFileName.endIndex, offsetBy: -6)
    let endIndex = imageFileName.index(imageFileName.endIndex, offsetBy: -4)
    let range = Range(uncheckedBounds: (beginIndex, endIndex))
    let scaleString = imageFileName.substring(with: range)
    
    // find the current json(2x or 3x)
    if var rootDict = json as? [String: Any], let imagesArray = rootDict["images"] as? [[String: Any]] {
        let newImagesArray = imagesArray.map { imageJson -> [String: Any] in
            var imageJson = imageJson
            if let currentObjectScale = imageJson["scale"] as? String, currentObjectScale == scaleString {
                imageJson["filename"] = imageFileName
            }
            return imageJson
        }
        
        // set back to result
        rootDict["images"] = newImagesArray
        return rootDict
    }
    return json
}

func getJson(at path: String) -> Any {
    let templateJsonData = try! Data(contentsOf: URL(fileURLWithPath: path))
    
    return try! JSONSerialization.jsonObject(with: templateJsonData, options: .allowFragments)
}

func generateRSourceCode() {
    let tempalteData = try! Data(contentsOf: URL(fileURLWithPath: "R.template.swift"))
    let templateString = String(data: tempalteData, encoding: .utf8)
    
    // map all images to generate code
    let generatedCode = allImageNames.map { imageName in
        return "\t\tpublic static let \(imageName): UIImage? = UIImage(named: \"\(imageName)\")"
    }.joined(separator: "\n")
    let fullCodeString = templateString?.replacingOccurrences(of: "// Images Template placeholder", with: generatedCode)
    
    let generatedFileUrl = URL(fileURLWithPath: outputCodePath + "/R.generated.swift")
    do {
        try fullCodeString?.data(using: .utf8)?.write(to: generatedFileUrl)
    } catch {
        print("!!!Generate source code error: \(error)")
    }
    
}

// remove existing first
do {
    print("removing existing Images.xcassets folder")
    try fileManager.removeItem(atPath: outputAssetsPath)
} catch {
    print("remove error \(error)")
}

// create output folder
try fileManager.createDirectory(atPath: outputAssetsPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions.rawValue: 0o766])

// enumerate all files
for element in fileManager.enumerator(atPath: inputImagesPath)! {
    if let pathString = element as? String {
        // skip app icon set processing
        let appIconFolderName = "AppIcon.appiconset"
        
        if pathString.hasSuffix(appIconFolderName) {
            // copy to destination
            let sourcePath = "\(inputImagesPath)/\(appIconFolderName)"
            let targetPath = "\(outputAssetsPath)/\(appIconFolderName)"
            
            try fileManager.copyItem(atPath: sourcePath, toPath: targetPath)
        } else if pathString.contains(appIconFolderName) {
            continue
        }
        
        let path = URL(fileURLWithPath: pathString)
        if supportedImageTypes.contains(path.pathExtension) {

            copyImageToOutput(sourcePath: pathString)
            print("===")
        }
    }
}

generateRSourceCode()

// print result
if errorItems.count == 0 {
    print(greenPrefix)
    print(String(repeating: "*", count: 45))
    print("*** \(allImageNames.count) images precessed successfully ***")
    print(String(repeating: "*", count: 45))
} else {
    print(redPrefix)
    print(String(repeating: "*", count: 45))
    print("*** Completed with error count: \(errorItems.count) ***")
    errorItems.forEach { item in
        print("reason: \(item.reason), path: \(item.path)")
    }
    print(String(repeating: "*", count: 45))
}
