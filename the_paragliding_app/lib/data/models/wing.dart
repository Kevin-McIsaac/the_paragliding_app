class Wing {
  final int? id;
  final String name;
  final String? manufacturer;
  final String? model;
  final String? size;
  final String? color;
  final DateTime? purchaseDate;
  final bool active;
  final String? notes;
  final DateTime? createdAt;

  Wing({
    this.id,
    required this.name,
    this.manufacturer,
    this.model,
    this.size,
    this.color,
    this.purchaseDate,
    this.active = true,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'manufacturer': manufacturer,
      'model': model,
      'size': size,
      'color': color,
      'purchase_date': purchaseDate?.toIso8601String(),
      'active': active ? 1 : 0,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Wing.fromMap(Map<String, dynamic> map) {
    return Wing(
      id: map['id'],
      name: map['name'],
      manufacturer: map['manufacturer'],
      model: map['model'],
      size: map['size'],
      color: map['color'],
      purchaseDate: map['purchase_date'] != null ? DateTime.parse(map['purchase_date']) : null,
      active: map['active'] == 1,
      notes: map['notes'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
    );
  }

  Wing copyWith({
    int? id,
    String? name,
    String? manufacturer,
    String? model,
    String? size,
    String? color,
    DateTime? purchaseDate,
    bool? active,
    String? notes,
    DateTime? createdAt,
  }) {
    return Wing(
      id: id ?? this.id,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      size: size ?? this.size,
      color: color ?? this.color,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Wing && other.id == id && id != null;
  }

  @override
  int get hashCode => id.hashCode;

  String get displayName {
    List<String> parts = [];
    if (manufacturer != null && manufacturer!.isNotEmpty) {
      parts.add(manufacturer!);
    }
    if (model != null && model!.isNotEmpty) {
      parts.add(model!);
    }
    
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    
    return name;
  }
}