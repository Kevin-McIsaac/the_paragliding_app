# OpenAIP Airspace API JSON Structure

This document describes the JSON structure returned by the OpenAIP Core API v1 airspaces endpoint.

## API Response Structure

The API returns a paginated response with the following top-level structure:

```json
{
  "items": [...],      // Array of airspace objects
  "limit": 500,        // API pagination limit
  "page": 1,          // Current page number
  "totalCount": 12,   // Total airspaces found
  "totalPages": 1     // Total pages available
}
```

## Airspace Object Properties

Each airspace in the `items` array contains 22 properties:

### Core Identification
- `_id`: MongoDB ObjectId (string)
- `name`: Human-readable airspace name (string)
  - Examples: "PERTH CTA C1", "JANDAKOT CONTROL ZONE (D)", "PERTH CENTRE"
- `country`: ISO country code (string)
  - Example: "AU" (Australia)
- `type`: Numeric airspace type code (integer)
  - `0`: Unknown
  - `1`: Restricted
  - `2`: Danger
  - `4`: CTR
  - `6`: TMA
  - `7`: TMA
  - `10`: FIR
  - `26`: CTA

### ICAO Classification System
- `icaoClass`: Numeric ICAO airspace class code (integer)
  - `0`: A 
  - `1`: B
  - `2`: C
  - `3`: D
  - `4`: E
  - `5`: F
  - `6`: G 
  - `8`: None

**Note**: `icaoClass: 8` indicates the airspace has no ICAO class assigned in the OpenAIP system, not missing data.

### ICAP Airspace Classifications Explainations

ICAO classifies airspace into seven classes (A through G) to provide different levels of air traffic s:w!ervices and separation. The classes range from highly controlled Class A to uncontrolled Class G:

- **Class A**: IFR only. All flights receive air traffic control service and are separated from all other traffic.

- **Class B**: IFR and VFR permitted. All flights receive air traffic control service and are separated from all other traffic.

- **Class C**: IFR and VFR permitted. All flights receive air traffic control service. IFR flights are separated from other IFR and VFR flights. VFR flights are separated from IFR flights and receive traffic information on other VFR flights.

- **Class D**: IFR and VFR permitted. All flights receive air traffic control service. IFR flights are separated from other IFR flights and receive traffic information on VFR flights. VFR flights receive traffic information on all other traffic.

- **Class E**: IFR and VFR permitted. IFR flights receive air traffic control service and are separated from other IFR flights. All flights receive traffic information as far as practical. VFR flights do not receive separation service.

- **Class F**: IFR and VFR permitted. IFR flights receive air traffic advisory service and all flights receive flight information service if requested. Class F is not implemented in many countries.

- **Class G**: Uncontrolled airspace. Only flight information service provided if requested. No separation service provided.




### Altitude Limits Structure
Both `lowerLimit` and `upperLimit` are objects with identical structure:

```json
{
  "value": 125,           // Altitude value (number)
  "unit": 6,             // Unit code (integer)
  "referenceDatum": 2    // Reference datum code (integer)
}
```

#### Unit Codes
- `1`: Feet (ft)
- `6`: Flight Level (FL)

#### Reference Datum Codes
- `0`: Ground/Surface (GND)
- `1`: Above Mean Sea Level (AMSL)
- `2`: Standard/Flight Level (STD)

#### Common Altitude Combinations (Perth Area)
- GND (0/0) to 1500 ft AMSL (1500/1/1)
- GND (0/0) to FL999 (999/6/2)
- 1500 ft AMSL to 2000 ft AMSL
- 2000 ft AMSL to 3500 ft AMSL
- 3500 ft AMSL to 4500 ft AMSL
- 4500 ft AMSL to 8500 ft AMSL
- 8500 ft AMSL to FL125
- FL125 to FL180
- FL125 to FL245
- FL180 to FL245
- FL245 to FL600

### Operational Status Flags
All boolean flags in the Perth dataset are `false`:
- `activity`: Activity type code (integer, always 0)
- `byNotam`: Activated by NOTAM (boolean)
- `onDemand`: Available on demand (boolean)
- `onRequest`: Available on request (boolean)
- `requestCompliance`: Requires compliance request (boolean)
- `specialAgreement`: Requires special agreement (boolean)

### Administrative Fields
- `__v`: MongoDB version field (integer)
- `createdAt`: ISO timestamp of creation (string)
- `updatedAt`: ISO timestamp of last update (string)
- `createdBy`: User ID who created record (string)
- `updatedBy`: User ID who last updated record (string)
- `dataIngestion`: Data ingestion metadata (object)
- `deletable`: Whether record can be deleted (boolean, always true)
- `hoursOfOperation`: Operating hours if applicable (array/null)
- `geometry`: GeoJSON geometry defining airspace boundaries (object)

## Perth Area Airspace Examples

Based on the sample data from coordinates (-32.1067, 115.8913):

### Control Areas (CTA)
- **PERTH CTA A**: Type 26, ICAO Class 0 (G), FL245-FL600
- **PERTH CTA C1**: Type 26, ICAO Class 2 (E), FL125-FL245
- **PERTH CTA C2**: Type 26, ICAO Class 2 (E), FL125-FL180
- **PERTH CTA C4-C7**: Type 26, ICAO Class 2 (E), various FL ranges

### Control Zones (CTR)
- **JANDAKOT CONTROL ZONE (D)**: Type 4, ICAO Class 3 (D), GND-1500ft AMSL

### Terminal Areas
- **PERTH/JANDAKOT**: Type 6, ICAO Class 8 (No class), 1500-2000ft AMSL

### Centers
- **PERTH CENTRE**: Type 0, ICAO Class 4 (C), 8500ft-FL125
- **CONTINENTAL AUSTRALIA CTA E1**: Type 0, ICAO Class 4 (C), FL180-FL245

## Implementation Notes

1. **Type Mapping**: The numeric type codes need to be mapped to aviation standard abbreviations (CTR, CTA, TMA, etc.)

2. **ICAO Class Display**: Use the numeric `icaoClass` code to determine the class letter (A-G), with code 8 meaning no class assigned.

3. **Altitude Conversion**: Flight levels (unit=6) represent hundreds of feet (FL125 = 12,500ft), while feet (unit=1) are direct values.

4. **Reference Datum**: Ground reference (referenceDatum=0) with value=0 should display as "GND".

5. **Sorting**: For altitude-based sorting, convert all altitudes to a common unit (feet) using the conversion rules.

## API Access

- **Endpoint**: `https://api.core.openaip.net/api/airspaces`
- **Parameters**: `bbox`, `limit`, `apiKey`
- **Authentication**: Requires valid API key
- **Rate Limits**: Subject to OpenAIP usage policies

## Airspace Types Reference

The OpenAIP `/airspaces` endpoint uses both numeric type codes and standard aviation abbreviations. Below are the complete airspace classifications:

### ATS Airspace Types
- **CTR** - Control Zone/Controlled Tower Region (airport control zone)
- **TMA** - Terminal Maneuvering Area (terminal control area)
- **FIR** - Flight Information Region
- **UIR** - Upper Information Region
- **CTA** - Control Area
- **UTA** - Upper Control Area
- **MATZ** - Military Aerodrome Traffic Zone

### Special Use Airspace
- **DANGER** or **D** - Danger Area (hazardous activities)
- **RESTRICTED** or **R** - Restricted Area (entry restricted)
- **PROHIBITED** or **P** - Prohibited Area (flight forbidden)
- **TMZ** - Transponder Mandatory Zone
- **RMZ** - Radio Mandatory Zone
- **TRA** - Temporary Reserved Area
- **TSA** - Temporary Segregated Area
- **MOA** - Military Operations Area
- **WAVE** - Wave/Mountain wave area
- **GLIDING** - Gliding area
- **SPORT** - Sport/recreational aviation area

## Sample Query

```bash
curl -H "Accept: application/json" \
  "https://api.core.openaip.net/api/airspaces?bbox=115.888,32.106,115.891,-32.100&limit=500&apiKey=YOUR_KEY"
```
