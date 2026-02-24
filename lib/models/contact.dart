/// Represents a contact in the address book.
class Contact {
  final String id;
  final String? firstName;
  final String? lastName;
  final String? company;
  final String? jobTitle;
  final List<ContactEmail> emails;
  final List<ContactPhone> phones;
  final ContactAddress? address;
  final String? notes;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Contact({
    required this.id,
    this.firstName,
    this.lastName,
    this.company,
    this.jobTitle,
    this.emails = const [],
    this.phones = const [],
    this.address,
    this.notes,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? emails.firstOrNull?.address ?? 'Unknown';
  }

  String get initials {
    final first = firstName?.isNotEmpty == true ? firstName![0] : '';
    final last = lastName?.isNotEmpty == true ? lastName![0] : '';
    if (first.isNotEmpty && last.isNotEmpty) return '$first$last'.toUpperCase();
    if (first.isNotEmpty) return first.toUpperCase();
    if (last.isNotEmpty) return last.toUpperCase();
    final email = emails.firstOrNull?.address ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  String get fileAs {
    if (lastName != null && firstName != null) return '$lastName, $firstName';
    return displayName;
  }

  Contact copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? company,
    String? jobTitle,
    List<ContactEmail>? emails,
    List<ContactPhone>? phones,
    ContactAddress? address,
    String? notes,
    String? photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      company: company ?? this.company,
      jobTitle: jobTitle ?? this.jobTitle,
      emails: emails ?? this.emails,
      phones: phones ?? this.phones,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'company': company,
        'jobTitle': jobTitle,
        'emails': emails.map((e) => '${e.label}|${e.address}').join(';'),
        'phones': phones.map((p) => '${p.label}|${p.number}').join(';'),
        'street': address?.street,
        'city': address?.city,
        'state': address?.state,
        'zipCode': address?.zipCode,
        'country': address?.country,
        'notes': notes,
        'photoPath': photoPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Contact.fromMap(Map<String, dynamic> map) => Contact(
        id: map['id'] as String,
        firstName: map['firstName'] as String?,
        lastName: map['lastName'] as String?,
        company: map['company'] as String?,
        jobTitle: map['jobTitle'] as String?,
        emails: _parseEmails(map['emails'] as String?),
        phones: _parsePhones(map['phones'] as String?),
        address: _parseAddress(map),
        notes: map['notes'] as String?,
        photoPath: map['photoPath'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );

  static List<ContactEmail> _parseEmails(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split(';').where((s) => s.isNotEmpty).map((s) {
      final parts = s.split('|');
      return ContactEmail(
        label: parts[0],
        address: parts.length > 1 ? parts[1] : parts[0],
      );
    }).toList();
  }

  static List<ContactPhone> _parsePhones(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split(';').where((s) => s.isNotEmpty).map((s) {
      final parts = s.split('|');
      return ContactPhone(
        label: parts[0],
        number: parts.length > 1 ? parts[1] : parts[0],
      );
    }).toList();
  }

  static ContactAddress? _parseAddress(Map<String, dynamic> map) {
    final street = map['street'] as String?;
    final city = map['city'] as String?;
    if (street == null && city == null) return null;
    return ContactAddress(
      street: street,
      city: city,
      state: map['state'] as String?,
      zipCode: map['zipCode'] as String?,
      country: map['country'] as String?,
    );
  }
}

class ContactEmail {
  final String label;
  final String address;

  const ContactEmail({required this.label, required this.address});
}

class ContactPhone {
  final String label;
  final String number;

  const ContactPhone({required this.label, required this.number});
}

class ContactAddress {
  final String? street;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;

  const ContactAddress({
    this.street,
    this.city,
    this.state,
    this.zipCode,
    this.country,
  });

  String get formatted {
    final parts = <String>[];
    if (street != null) parts.add(street!);
    final cityLine = [city, state, zipCode]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    if (cityLine.isNotEmpty) parts.add(cityLine);
    if (country != null) parts.add(country!);
    return parts.join('\n');
  }
}
