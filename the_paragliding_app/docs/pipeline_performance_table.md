# Airspace Pipeline Performance Summary

## Complete Pipeline Performance Table

| **Stage** | **Perth (City)** | **Australia (Country)** | **France (Dense)** |
|-----------|------------------|-------------------------|-------------------|
| **Viewport** | 50×50 km | 4000×3000 km | 1000×1000 km |
| **Input Polygons** | 20 | 1,819 | 1,631 |
| **Output Polygons** | 18 | 1,456 | 1,205 |
| **Eliminated** | 2 (10%) | 363 (20%) | 426 (26%) |

### Stage-by-Stage Timing (milliseconds)

| **Stage** | **Perth** | **Australia** | **France** | **Notes** |
|-----------|-----------|---------------|------------|-----------|
| **1. INGESTION** | | | | |
| Download | 16,000* | 16,000 | 7,500 | One-time, cached |
| Parse GeoJSON | 200* | 2,000 | 1,800 | One-time |
| Process | 200* | 2,000 | 1,800 | One-time |
| | | | | |
| **2. DATABASE** | | | | |
| Binary encode | 50* | 500 | 450 | One-time |
| Batch insert | 350* | 3,500 | 2,400 | One-time |
| Index update | 10* | 100 | 90 | One-time |
| | | | | |
| **3. QUERY** | **8** | **120** | **95** | Per frame |
| SQL execute | 3 | 45 | 40 | Spatial filter |
| Data fetch | 4 | 70 | 50 | Load rows |
| ClipperData | 1 | 5 | 5 | Zero-copy view |
| | | | | |
| **4. CLIPPING** | **12** | **3,200** | **2,450** | Per frame |
| Setup/sort | 1 | 10 | 8 | |
| Comparisons | 190 | 1,654,821 | 1,328,265 | O(n²) total |
| - Altitude reject | 114 | 743,469 | 464,892 | Early exit |
| - Bounds reject | 23 | 364,340 | 215,843 | Spatial filter |
| - Actual clips | 5 | 82,000 | 250,000 | Clipper2 ops |
| Clipper2 time | 10 | 3,150 | 2,400 | Core algorithm |
| | | | | |
| **5. RENDERING** | **5** | **85** | **70** | Per frame |
| To LatLng | 2 | 35 | 30 | Display format |
| Create widgets | 2 | 30 | 25 | Flutter polygons |
| GPU render | 1 | 20 | 15 | Per frame |

*Perth uses subset of Australia data

## Runtime Performance Summary

| **Metric** | **Perth** | **Australia** | **France** |
|------------|-----------|---------------|------------|
| **Query + Clip + Render** | **25ms** | **3,405ms** | **2,615ms** |
| **Frame Rate Capability** | 40 FPS | 0.3 FPS | 0.4 FPS |
| **User Experience** | Smooth | Need progress bar | Need progress bar |

## Optimization Impact

### Current (With Int32 Optimization)

| **Stage** | **Perth** | **Australia** | **France** |
|-----------|-----------|---------------|------------|
| Query | 8ms | 120ms | 95ms |
| Clipping | 12ms | 3,200ms | 2,450ms |
| Rendering | 5ms | 85ms | 70ms |
| **Total** | **25ms** | **3,405ms** | **2,615ms** |

### After Query Optimization (Proposed)

| **Stage** | **Perth** | **Australia** | **France** | **Improvement** |
|-----------|-----------|---------------|------------|-----------------|
| Query | 3ms (-63%) | 40ms (-67%) | 30ms (-68%) | Covering index |
| Clipping | 12ms | 3,200ms | 2,450ms | No change |
| Rendering | 5ms | 85ms | 70ms | No change |
| **Total** | **20ms** | **3,325ms** | **2,550ms** | **2-20% faster** |

### After R-tree Clipping (Future)

| **Stage** | **Perth** | **Australia** | **France** | **Improvement** |
|-----------|-----------|---------------|------------|-----------------|
| Query | 3ms | 40ms | 30ms | Optimized |
| Clipping | 5ms (-58%) | 400ms (-87%) | 350ms (-86%) | O(n log n) |
| Rendering | 5ms | 85ms | 70ms | No change |
| **Total** | **13ms** | **525ms** | **450ms** | **48-85% faster** |

## Performance Bottleneck Analysis

| **Scale** | **Bottleneck** | **% of Runtime** | **Solution** |
|-----------|----------------|------------------|--------------|
| **City (Perth)** | Query | 32% | Covering index |
| **Country (Australia)** | Clipping | 94% | R-tree algorithm |
| **Dense (France)** | Clipping | 93% | R-tree algorithm |

## Clipping Complexity Analysis

| **Metric** | **Perth** | **Australia** | **France** |
|------------|-----------|---------------|------------|
| **Theoretical O(n²)** | 190 | 1,654,821 | 1,328,265 |
| **After altitude filter** | 76 (40%) | 911,352 (55%) | 863,373 (65%) |
| **After bounds filter** | 53 (28%) | 547,012 (33%) | 647,530 (49%) |
| **Actual clip operations** | 5 (2.6%) | 82,000 (5%) | 250,000 (19%) |
| **Efficiency** | 97.4% skip | 95% skip | 81% skip |

## Key Insights

1. **Perth**: Query optimization would provide 20% overall improvement
2. **Australia/France**: Clipping dominates - need algorithmic change
3. **Int32 optimization**: Already delivered 25% improvement
4. **Next priority**: R-tree for O(n log n) clipping would make country-scale interactive

---
*Performance measured on Chromebox Reference Emulator*
*Date: 2025-09-20*