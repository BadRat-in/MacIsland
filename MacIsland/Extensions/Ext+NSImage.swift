//
//  Ext+NSImage.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import Cocoa

extension NSImage {
    var pngRepresentation: Data {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .init()
        }
        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        imageRep.size = size
        return imageRep.representation(using: .png, properties: [:]) ?? .init()
    }
    
    func averageColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = cgImage.bitsPerComponent
        let bytesPerRow = cgImage.bytesPerRow
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context?.data else {
            return nil
        }
        
        let data = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * 4)
                let r = CGFloat(data[offset]) / 255.0
                let g = CGFloat(data[offset + 1]) / 255.0
                let b = CGFloat(data[offset + 2]) / 255.0
                
                red += r
                green += g
                blue += b
                count += 1
            }
        }
        
        if count > 0 {
            red /= count
            green /= count
            blue /= count
        }

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
