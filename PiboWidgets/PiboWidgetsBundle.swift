//
//  PiboWidgetsBundle.swift
//  PiboWidgets
//
//  Created by Trevorlink on 5/28/26.
//

import WidgetKit
import SwiftUI

@main
struct PiboWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PiboWidgets()
        PiboWidgetsLiveActivity()
        WalkDoodleLiveActivity()
    }
}
