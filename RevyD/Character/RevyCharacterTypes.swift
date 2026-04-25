import Foundation

enum RevyFacing {
    case front
    case left
    case right
}

enum RevyExpression {
    case idle       // default
    case thinking   // blue tint — while Claude processes
    case happy      // green tint — debrief complete, sync done
    case alert      // red tint — overdue commitments, errors
}
