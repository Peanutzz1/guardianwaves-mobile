import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility to convert Firestore timestamp-like values into [DateTime].
DateTime? parseFirestoreTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;

  if (value is Map) {
    final seconds = value['seconds'];
    final nanoseconds = value['nanoseconds'] ?? 0;
    if (seconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000) + (nanoseconds is int ? nanoseconds ~/ 1000000 : 0),
        isUtc: false,
      );
    }
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  return null;
}

/// Metadata summary for a vessel document used across admin screens.
class VesselSummary {
  const VesselSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.rawData,
    this.imoNumber,
    this.companyName,
    this.vesselType,
    this.master,
    this.contactNumber,
    this.grossTonnage,
    this.submittedAt,
    this.reviewedAt,
  });

  factory VesselSummary.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};

    final status = (data['submissionStatus'] ?? data['status'] ?? 'pending')
        .toString()
        .toLowerCase();

    num? gross;
    final grossRaw = data['grossTonnage'];
    if (grossRaw is num) {
      gross = grossRaw;
    } else if (grossRaw is String) {
      gross = num.tryParse(grossRaw);
    }

    return VesselSummary(
      id: snapshot.id,
      name: (data['vesselName'] ?? data['name'] ?? 'Unnamed Vessel').toString(),
      status: status,
      imoNumber: _asString(data['imoNumber']),
      companyName: _asString(
        data['companyOwner'] ?? data['companyName'] ?? data['shippingCompany'],
      ),
      vesselType: _asString(data['vesselType']),
      master: _asString(
        data['master'] ?? data['captain'] ?? data['masterName'],
      ),
      contactNumber: _asString(
        data['contactNumber'] ?? data['phoneNumber'] ?? data['contactPerson'],
      ),
      grossTonnage: gross,
      submittedAt: parseFirestoreTimestamp(
        data['submittedAt'] ?? data['createdAt'],
      ),
      reviewedAt: parseFirestoreTimestamp(
        data['reviewedAt'] ?? data['approvedAt'],
      ),
      rawData: Map<String, dynamic>.from(data),
    );
  }

  final String id;
  final String name;
  final String status;
  final String? imoNumber;
  final String? companyName;
  final String? vesselType;
  final String? master;
  final String? contactNumber;
  final num? grossTonnage;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final Map<String, dynamic> rawData;

  bool get isPending => !isApproved && !isDeclined;
  bool get isApproved => status == 'approved' || status == 'accepted';
  bool get isDeclined => status == 'declined' || status == 'rejected';

  VesselSummary copyWith({String? status, DateTime? reviewedAt}) {
    return VesselSummary(
      id: id,
      name: name,
      status: status ?? this.status,
      rawData: rawData,
      imoNumber: imoNumber,
      companyName: companyName,
      vesselType: vesselType,
      master: master,
      contactNumber: contactNumber,
      grossTonnage: grossTonnage,
      submittedAt: submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }
}

/// Summary of a vessel access request for quick display and actions.
class AccessRequestSummary {
  const AccessRequestSummary({
    required this.id,
    required this.vesselName,
    required this.requesterEmail,
    required this.status,
    this.requesterName,
    this.vesselId,
    this.requestedAt,
    this.requesterId,
  });

  factory AccessRequestSummary.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};

    return AccessRequestSummary(
      id: snapshot.id,
      vesselName: _asString(data['vesselName']) ?? 'Unknown Vessel',
      requesterEmail:
          _asString(data['requesterEmail']) ?? 'unknown@guardianwaves.app',
      requesterName: _asString(data['requesterName']),
      requesterId: _asString(data['requesterId']),
      vesselId: _asString(data['vesselId']),
      status: (data['status'] ?? 'pending').toString().toLowerCase(),
      requestedAt: parseFirestoreTimestamp(
        data['requestedAt'] ?? data['createdAt'],
      ),
    );
  }

  AccessRequestSummary copyWith({String? status, DateTime? requestedAt}) {
    return AccessRequestSummary(
      id: id,
      vesselName: vesselName,
      requesterEmail: requesterEmail,
      requesterName: requesterName,
      requesterId: requesterId,
      vesselId: vesselId,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
    );
  }

  final String id;
  final String vesselName;
  final String requesterEmail;
  final String? requesterName;
  final String? requesterId;
  final String? vesselId;
  final String status;
  final DateTime? requestedAt;

  bool get isPending => !isApproved && !isDeclined;
  bool get isApproved => status == 'approved' || status == 'accepted';
  bool get isDeclined => status == 'declined' || status == 'rejected';
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}
