import Foundation

extension UnitKind {
    /// Маппинг kind → роль слота в DistrictTemplate.
    /// Compile-time exhaustive: новый UnitKind не пройдёт без явного case.
    var preferredSlotRole: SlotRole {
        switch self {
        // Residential (12)
        case .dugout, .shack, .hut, .farmHouse, .house, .twoStoryHouse,
             .stoneHouse, .townhouse, .tenement, .manor, .villa, .palace:
            return .residential

        // Infrastructure
        case .well:               return .well
        case .road:               return .road
        case .gate:               return .gate
        case .bridge, .cistern, .irrigationCanal, .aqueduct:
                                  return .road       // линейная инфра — road-слот
        case .lighthouse:         return .monumental
        case .pier:               return .road       // мостки — линейная инфра
        case .warehouse:          return .warehouse

        // Production
        case .farm, .fishingPier: return .farm
        case .workshop, .raw, .forge, .pottery, .brewery, .sawmill,
             .quarry, .mine, .factory, .largeWarehouse:
                                  return .workshop

        // Social
        case .tavern, .plaza, .market, .forum:
                                  return .market
        case .bathhouse, .hospital:
                                  return .bath
        case .school, .library, .theater:
                                  return .school
        case .obelisk:            return .obelisk

        // Religious
        case .chapel, .temple:    return .temple
        case .cathedral, .pyramid:
                                  return .monumental

        // Military
        case .watchtower, .barracks:
                                  return .gate
        case .shipyard:           return .farm  // прод на воде, ближе к farm/pier
        }
    }
}
