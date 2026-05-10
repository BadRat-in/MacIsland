//
//  ColorButton.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import SwiftUI
import ColorfulX
import Pow
import UniformTypeIdentifiers

struct ColorButton: View {
    let cornerRadius: CGFloat
    let color: [Color]
    let image: Image
    let title: LocalizedStringKey

    @State var hover: Bool = false

    var body: some View {
        ColorfulView(
            color: .constant(color),
            speed: .constant(0)
        )
        .opacity(0.5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay { VStack(spacing: 8) {
            Text("888888")
                .hidden()
                .overlay {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            Text(title)
        }
        .font(.system(.headline, design: .rounded))
        .contentShape(Rectangle()) }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
    }
}
