//  Mobility.swift
//  Ravns
//
//  Advisory mobility flag from the onboarding range-of-motion questions. Mobility is an *enabler*,
//  not a fitness axis — it gates how well you express strength/running in the stations (wall-ball
//  depth, lunges, burpees) — so it lives beside the quadrant as a flag, never inside the score.

import Foundation

enum MobilityFlag: String {
    case mobile, limited, restricted

    var label: String {
        switch self {
        case .mobile:     return "Mobile"
        case .limited:    return "Limited"
        case .restricted: return "Restricted"
        }
    }

    /// Short read for the Athlete "the read" card + coach context.
    var read: String {
        switch self {
        case .mobile:
            return "Depth + range are there — stations won't no-rep on mobility."
        case .limited:
            return "Some range limits — watch wall-ball depth and lunge form when you fatigue."
        case .restricted:
            return "Restricted range — wall-ball depth, lunges, and burpees will no-rep or strain. Mobility is a limiter; train it."
        }
    }
}

enum Mobility {
    static func flag(score: Double) -> MobilityFlag {
        switch score {
        case 0.7...:     return .mobile
        case 0.4..<0.7:  return .limited
        default:         return .restricted
        }
    }
}
