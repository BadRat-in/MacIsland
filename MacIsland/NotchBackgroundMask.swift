//
//  NotchBackgroundMask.swift
//  MacIsland
//
//  Created by Ravindra Singh on 25/08/25.
//

import SwiftUI

struct NotchBackgroundMask: View {
    let size: CGSize
    let cornerRadius: CGFloat
    let spacing: CGFloat
    
    var body: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius
            ))
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: cornerRadius, height: cornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topTrailingRadius: cornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: cornerRadius + spacing,
                            height: cornerRadius + spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -cornerRadius - spacing + 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: cornerRadius, height: cornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topLeadingRadius: cornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: cornerRadius + spacing,
                            height: cornerRadius + spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: cornerRadius + spacing - 0.5, y: -0.5)
            }
    }
}

#Preview{
    NotchBackgroundMask(
        size: CGSize(
            width: 300,
            height: 60),
        cornerRadius: 8,
        spacing: 4
    )
}
