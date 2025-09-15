/// Enum definitions for OpenAIP airspace types and ICAO classes
/// Provides type safety and centralized mapping for airspace data

/// OpenAIP airspace type classifications
/// Based on OpenAIP Core API documentation
enum AirspaceType {
  other(0, 'Other', 'Unknown/Other', 'Other airspace type'),
  restricted(1, 'R', 'Restricted', 'Restricted Area - entry restricted'),
  danger(2, 'D', 'Danger', 'Danger Area - hazardous activities'),
  prohibited(3, 'P', 'Prohibited', 'Prohibited Area - flight forbidden'),
  ctr(4, 'CTR', 'Control Zone', 'Controlled Tower Region (airport control zone)'),
  tmz(5, 'TMZ', 'TMZ', 'Transponder Mandatory Zone'),
  rmz(6, 'RMZ', 'RMZ', 'Radio Mandatory Zone'),
  tma(7, 'TMA', 'Terminal Area', 'Terminal Maneuvering Area (terminal control area)'),
  tra(8, 'TRA', 'TRA', 'Temporary Reserved Area'),
  tsa(9, 'TSA', 'TSA', 'Temporary Segregated Area'),
  fir(10, 'FIR', 'Flight Info Region', 'Flight Information Region'),
  uir(11, 'UIR', 'UIR', 'Upper Flight Information Region'),
  adiz(12, 'ADIZ', 'ADIZ', 'Air Defense Identification Zone'),
  atz(13, 'ATZ', 'ATZ', 'Airport Traffic Zone'),
  matz(14, 'MATZ', 'MATZ', 'Military Airport Traffic Zone'),
  airway(15, 'AWY', 'Airway', 'Airway'),
  mtr(16, 'MTR', 'MTR', 'Military Training Route'),
  alert(17, 'A', 'Alert', 'Alert Area'),
  warning(18, 'W', 'Warning', 'Warning Area'),
  protected(19, 'PROT', 'Protected', 'Protected Area'),
  htz(20, 'HTZ', 'HTZ', 'Helicopter Traffic Zone'),
  gliding(21, 'GLIDING', 'Gliding', 'Gliding Sector'),
  trp(22, 'TRP', 'TRP', 'Transponder Setting'),
  tiz(23, 'TIZ', 'TIZ', 'Traffic Information Zone'),
  tia(24, 'TIA', 'TIA', 'Traffic Information Area'),
  mta(25, 'MTA', 'MTA', 'Military Training Area'),
  cta(26, 'CTA', 'Control Area', 'Control Area'),
  acc(27, 'ACC', 'ACC', 'ACC Sector'),
  sport(28, 'SPORT', 'Sport/Recreation', 'Aerial Sporting Or Recreational Activity'),
  lowAltRestriction(29, 'LAR', 'Low Alt Restriction', 'Low Altitude Overflight Restriction'),
  militaryRoute(30, 'MRT', 'Military Route', 'Military Route'),
  tfr(31, 'TFR', 'TFR', 'TSA/TRA Feeding Route'),
  vfrSector(32, 'VFR', 'VFR Sector', 'VFR Sector'),
  fisSector(33, 'FIS', 'FIS Sector', 'FIS Sector'),
  lta(34, 'LTA', 'LTA', 'Lower Traffic Area'),
  uta(35, 'UTA', 'UTA', 'Upper Traffic Area'),
  mctr(36, 'MCTR', 'MCTR', 'Military Controlled Tower Region');

  const AirspaceType(this.code, this.abbreviation, this.displayName, this.description);

  final int code;
  final String abbreviation;
  final String displayName;
  final String description;

  /// Convert from OpenAIP numeric code to enum
  static AirspaceType fromCode(int code) {
    for (final type in AirspaceType.values) {
      if (type.code == code) return type;
    }
    return AirspaceType.other; // Default to other for unknown codes
  }

  /// Get all types that should be hidden by default (large coverage areas)
  static Set<AirspaceType> get defaultHiddenTypes => {
    AirspaceType.fir,
    AirspaceType.uir,
    AirspaceType.other,
  };

  /// Check if this type should be hidden by default
  bool get isHiddenByDefault => defaultHiddenTypes.contains(this);
}

/// ICAO airspace class classifications
/// Based on International Civil Aviation Organization standards
enum IcaoClass {
  classA(0, 'A', 'Class A', 'IFR only. All flights receive ATC service and separation'),
  classB(1, 'B', 'Class B', 'IFR/VFR. All flights receive ATC service and separation'),
  classC(2, 'C', 'Class C', 'IFR/VFR. All receive ATC, IFR separated from all'),
  classD(3, 'D', 'Class D', 'IFR/VFR. All receive ATC, IFR separated from IFR only'),
  classE(4, 'E', 'Class E', 'IFR/VFR. IFR receives ATC service and separation'),
  classF(5, 'F', 'Class F', 'IFR/VFR. Advisory service, not widely implemented'),
  classG(6, 'G', 'Class G', 'Uncontrolled airspace, flight information only'),
  none(8, 'None', 'No Class', 'No ICAO class assigned in the OpenAIP system');

  const IcaoClass(this.code, this.abbreviation, this.displayName, this.description);

  final int code;
  final String abbreviation;
  final String displayName;
  final String description;

  /// Convert from OpenAIP numeric code to enum
  static IcaoClass? fromCode(int? code) {
    if (code == null) return null;
    for (final icaoClass in IcaoClass.values) {
      if (icaoClass.code == code) return icaoClass;
    }
    return IcaoClass.none; // Default to none for unknown codes
  }

  /// Get all classes that should be hidden by default
  static Set<IcaoClass> get defaultHiddenClasses => {
    IcaoClass.classA, // High altitude, primarily commercial
    IcaoClass.classE, // Less critical for VFR
    IcaoClass.classF, // Not widely implemented
  };

  /// Check if this class should be hidden by default
  bool get isHiddenByDefault => defaultHiddenClasses.contains(this);
}

/// Extension methods for easier use in UI components
extension AirspaceTypeExtension on AirspaceType {
  /// Get tooltip message for UI display
  String get tooltip => '$displayName - $description';

  /// Get color-coded priority for rendering order (lower = render on top)
  int get renderPriority {
    switch (this) {
      case AirspaceType.prohibited:
      case AirspaceType.danger:
        return 1; // Highest priority (most critical)
      case AirspaceType.restricted:
        return 2;
      case AirspaceType.ctr:
      case AirspaceType.atz:
        return 3;
      case AirspaceType.tma:
      case AirspaceType.cta:
        return 4;
      case AirspaceType.tmz:
      case AirspaceType.rmz:
        return 5;
      case AirspaceType.fir:
      case AirspaceType.uir:
        return 99; // Lowest priority (background)
      default:
        return 10;
    }
  }
}

extension IcaoClassExtension on IcaoClass {
  /// Get tooltip message for UI display
  String get tooltip => '$displayName - $description';
}