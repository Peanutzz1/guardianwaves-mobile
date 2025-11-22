class DocumentItem {
  DocumentItem({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.vesselId,
    required this.vesselName,
    required this.hasExpiry,
    this.expiryDate,
    this.issuedDate,
    this.fileUrl,
    this.crewName,
    this.photoUrls,
  });

  final String id;
  final String name;
  final String type;
  final String category;
  final String vesselId;
  final String vesselName;
  final bool hasExpiry;
  final dynamic expiryDate;
  final dynamic issuedDate;
  final String? fileUrl;
  final String? crewName;
  final List<String>? photoUrls; // Array of all photo URLs
}

