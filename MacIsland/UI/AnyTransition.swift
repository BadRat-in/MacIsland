//
//  AnyTransition.swift
//  MacIsland
//
//  Created by Ravindra Singh on 25/08/25.
//

import SwiftUI

extension AnyTransition {
    static var expandWidth: AnyTransition {
        .modifier(
            active: ScaleEffectX(amount: 0),
            identity: ScaleEffectX(amount: 1)
        )
    }
}

struct ScaleEffectX: ViewModifier {
    var amount: CGFloat
    
    func body(content: Content) -> some View {
        content.scaleEffect(x: amount, y: 1, anchor: .center)
    }
}
