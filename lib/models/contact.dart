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
    final first = firstName?.trim() ?? '';
    final last = lastName?.trim() ?? '';
    if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return last;
    if (company != null && company!.trim().isNotEmpty) return company!.trim();
    return emails.firstOrNull?.address ?? 'Unknown';
  }

  String get initials {
    final first = firstName?.trim().isNotEmpty == true ? firstName!.trim()[0] : '';
    final last = lastName?.trim().isNotEmpty == true ? lastName!.trim()[0] : '';
    if (first.isNotEmpty && last.isNotEmpty) return '$first$last'.toUpperCase();
    if (first.isNotEmpty) return first.toUpperCase();
    if (last.isNotEmpty) return last.toUpperCase();
    final name = displayName;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String get fileAs {
    final first = firstName?.trim() ?? '';
    final last = lastName?.trim() ?? '';
    if (last.isNotEmpty && first.isNotEmpty) return '$last, $first';
    return displayName;
  }

  /// The primary email address, if any.
  String? get primaryEmail => emails.firstOrNull?.address;

  /// Whether any of this contact's addresses equals [address].
  bool hasEmail(String address) => emails
      .any((e) => e.address.toLowerCase() == address.trim().toLowerCase());

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

  /// Returns a copy with the editable fields replaced, allowing them to be
  /// cleared (unlike [copyWith], which treats null as "keep").
  Contact withDetails({
    required String? firstName,
    required String? lastName,
    required String? company,
    required String? jobTitle,
    required List<ContactEmail> emails,
    required List<ContactPhone> phones,
    required ContactAddress? address,
    required String? notes,
    required DateTime updatedAt,
  }) {
    return Contact(
      id: id,
      firstName: firstName,
      lastName: lastName,
      company: company,
      jobTitle: jobTitle,
      emails: emails,
      phones: phones,
      address: address,
      notes: notes,
      photoPath: photoPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'company': company,
        'jobTitle': jobTitle,
        'emails': emails.map((e) => e.toMap()).toList(),
        'phones': phones.map((p) => p.toMap()).toList(),
        'address': address?.toMap(),
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
        emails: (map['emails'] as List? ?? const [])
            .map((e) => ContactEmail.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        phones: (map['phones'] as List? ?? const [])
            .map((p) => ContactPhone.fromMap((p as Map).cast<String, dynamic>()))
            .toList(),
        address: map['address'] == null
            ? null
            : ContactAddress.fromMap(
                (map['address'] as Map).cast<String, dynamic>()),
        notes: map['notes'] as String?,
        photoPath: map['photoPath'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
}

class ContactEmail {
  final String label;
  final String address;

  const ContactEmail({required this.label, required this.address});

  Map<String, dynamic> toMap() => {'label': label, 'address': address};

  factory ContactEmail.fromMap(Map<String, dynamic> map) => ContactEmail(
        label: map['label'] as String? ?? 'Email',
        address: map['address'] as String? ?? '',
      );
}

class ContactPhone {
  final String label;
  final String number;

  const ContactPhone({required this.label, required this.number});

  Map<String, dynamic> toMap() => {'label': label, 'number': number};

  factory ContactPhone.fromMap(Map<String, dynamic> map) => ContactPhone(
        label: map['label'] as String? ?? 'Phone',
        number: map['number'] as String? ?? '',
      );
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

  bool get isEmpty => [street, city, state, zipCode, country]
      .every((s) => s == null || s.trim().isEmpty);

  String get formatted {
    final parts = <String>[];
    if (street != null && street!.isNotEmpty) parts.add(street!);
    final cityLine = [city, state, zipCode]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    if (cityLine.isNotEmpty) parts.add(cityLine);
    if (country != null && country!.isNotEmpty) parts.add(country!);
    return parts.join('\n');
  }

  Map<String, dynamic> toMap() => {
        'street': street,
        'city': city,
        'state': state,
        'zipCode': zipCode,
        'country': country,
      };

  factory ContactAddress.fromMap(Map<String, dynamic> map) => ContactAddress(
        street: map['street'] as String?,
        city: map['city'] as String?,
        state: map['state'] as String?,
        zipCode: map['zipCode'] as String?,
        country: map['country'] as String?,
      );
}

/// A contact group (distribution list). Members are either contacts from the
/// address book (by id) or one-off addresses.
class ContactGroup {
  final String id;
  final String name;
  final List<String> memberIds;
  final List<String> extraAddresses;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ContactGroup({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.extraAddresses = const [],
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  int get memberCount => memberIds.length + extraAddresses.length;

  /// Resolves the group's email addresses using [contactsById], skipping
  /// members that were deleted or have no email address.
  List<String> resolveAddresses(Map<String, Contact> contactsById) {
    final seen = <String>{};
    final result = <String>[];
    for (final id in memberIds) {
      final email = contactsById[id]?.primaryEmail;
      if (email != null && seen.add(email.toLowerCase())) result.add(email);
    }
    for (final address in extraAddresses) {
      if (seen.add(address.toLowerCase())) result.add(address);
    }
    return result;
  }

  ContactGroup copyWith({
    String? name,
    List<String>? memberIds,
    List<String>? extraAddresses,
    String? notes,
    DateTime? updatedAt,
  }) {
    return ContactGroup(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      extraAddresses: extraAddresses ?? this.extraAddresses,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'extraAddresses': extraAddresses,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ContactGroup.fromMap(Map<String, dynamic> map) => ContactGroup(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Group',
        memberIds: (map['memberIds'] as List? ?? const []).cast<String>(),
        extraAddresses:
            (map['extraAddresses'] as List? ?? const []).cast<String>(),
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
}
