# OpenAIP Airspace API JSON Structure

This document describes the JSON structure returned by the OpenAIP 
Core API v1 airspaces endpoint.

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
- `type`: Numeric airspace type code (integer 0 - 36)
  - `0`: Other
  - `1`: Restricted
  - `2`: Danger
  - `3`: Prohibited
  - `4`: Controlled Tower Region (CTR)
  - `5`: Transponder Mandatory Zone (TMZ)
  - `6`: Radio Mandatory Zone (RMZ)
  - `7`: Terminal Maneuvering Area (TMA)
  - `8`: Temporary Reserved Area (TRA)
  - `9`: Temporary Segregated Area (TSA)
  - `10`: Flight Information Region (FIR)
  - `11`: Upper Flight Information Region (UIR)
  - `12`: Air Defense Identification Zone (ADIZ)
  - `13`: Airport Traffic Zone (ATZ)
  - `14`: Military Airport Traffic Zone (MATZ)
  - `15`: Airway
  - `16`: Military Training Route (MTR)
  - `17`: Alert Area
  - `18`: Warning Area
  - `19`: Protected Area
  - `20`: Helicopter Traffic Zone (HTZ)
  - `21`: Gliding Sector
  - `22`: Transponder Setting (TRP)
  - `23`: Traffic Information Zone (TIZ)
  - `24`: Traffic Information Area (TIA)
  - `25`: Military Training Area (MTA)
  - `26`: Control Area (CTA)
  - `27`: ACC Sector (ACC)
  - `28`: Aerial Sporting Or Recreational Activity
  - `29`: Low Altitude Overflight Restriction
  - `30`: Military Route (MRT)
  - `31`: TSA/TRA Feeding Route (TFR)
  - `32`: VFR Sector
  - `33`: FIS Sector
  - `34`: Lower Traffic Area (LTA)
  - `35`: Upper Traffic Area (UTA)
  - `36`: Military Controlled Tower Region (MCTR)

### ICAO Classification System
- `icaoClass`: Numeric ICAO airspace class code (integer 0-6, 8)
  - `0`: A
  - `1`: B
  - `2`: C
  - `3`: D
  - `4`: E
  - `5`: F
  - `6`: G
  - `8`: None

**Note**: `icaoClass: 8` indicates the airspace has no ICAO class assigned in the OpenAIP system, not missing data.

### ICAO Airspace Classifications Explanations

OpenAIP uses International Civil Aviation Organization (ICAO) classifications. THese classify airspace into seven classes (A through G) to provide different levels of air traffic services and separation. The classes range from highly controlled Class A to uncontrolled Class G:

#### Controlled Airspace (Classes A-E)

- **Class A**: **IFR only**. High-level, restrictive airspace primarily for commercial and passenger jets, requiring advanced IFR clearance. All flights receive air traffic control service and are separated from all other traffic.

- **Class B**: **IFR and VFR**. Airspace surrounding major airports, with specific requirements for IFR and VFR flight, including clearance and ATC services. All flights receive air traffic control service and are separated from all other traffic.

- **Class C**: **IFR and VFR**. Airspace surrounding major airports, with specific requirements for IFR and VFR flight, including clearance and ATC services. All flights receive air traffic control service. IFR flights are separated from other IFR and VFR flights. VFR flights are separated from IFR flights and receive traffic information on other VFR flights.

- **Class D**: **IFR and VFR**. Airspace surrounding major airports, with specific requirements for IFR and VFR flight, including clearance and ATC services. All flights receive air traffic control service. IFR flights are separated from other IFR flights and receive traffic information on VFR flights. VFR flights receive traffic information on all other traffic.

- **Class E**: **IFR and VFR**. Mid-level, en route controlled airspace with less stringent rules than lower classes. IFR flights receive air traffic control service and are separated from other IFR flights. All flights receive traffic information as far as practical. VFR flights do not receive separation service.

#### Uncontrolled Airspace (Classes F-G)

- **Class F**: **IFR and VFR**. IFR flights receive air traffic advisory service and all flights receive flight information service if requested. Class F is not implemented in many countries.

- **Class G**: **Uncontrolled**. Pilots are responsible for "see and avoid" and maintaining separation, as ATC services and separation are not provided. Only flight information service provided if requested. No separation service provided.

#### Special Use Airspace (SUA)

SUA areas have specific limitations or rules for safety, found on flight charts and including:

- **Prohibited Areas**: Flight is forbidden.
- **Restricted Areas**: Flight is restricted and requires permission to enter.
- **Warning Areas**: Areas with a high volume of military activity but do not pose the same danger as restricted areas.
- **Military Operations Areas (MOAs)**: Used to separate military flight training from civilian air traffic.
- **Alert Areas**: Areas with a high volume of pilot activity, though not necessarily dangerous.
- **Controlled Firing Areas (CFAs)**: Areas where activities, like firing, pose a potential hazard and can be temporarily suspended to permit VFR flight.

OpenAIP data includes details on the specific characteristics of each airspace, including its boundaries, altitudes, and operational times to ensure safe and efficient flight.

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

## Implementation Notes

1. **Type Mapping**: The numeric type codes need to be mapped to aviation standard abbreviations (CTR, CTA, TMA, etc.) If there isn't a mapping, show the numerical value.


2. **Altitude Conversion**: Flight levels (unit=6) represent hundreds of feet (FL125 = 12,500ft), while feet (unit=1) are direct values.

3. **Reference Datum**: Ground reference (referenceDatum=0) with value=0 should display as "GND".

4. **Sorting**: For altitude-based sorting, convert all altitudes to a common unit (feet) using the conversion rules.

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