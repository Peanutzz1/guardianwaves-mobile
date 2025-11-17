// Maritime Document Data Extraction Service
// Enhanced for Philippine maritime certificates and vessel documents

class DataExtractionService {
  
  // Enhanced certificate extraction for Philippine maritime certificates
  Map<String, dynamic> extractCertificateData(String text) {
    print('Extracting certificate data from text...');
    print('OCR Text sample: ${text.length > 1000 ? text.substring(0, 1000) : text}');
    
    final certificateData = <String, dynamic>{};

    // Certificate type patterns
    final certificateTypePatterns = [
      RegExp(r'CERTIFICATE\s+OF\s+PUBLIC\s+CONVENIENCE', caseSensitive: false),
      RegExp(r'SAFETY\s+MANAGEMENT\s+CERTIFICATE', caseSensitive: false),
      RegExp(r'CARGO\s+SECURING\s+MANUAL\s+COMPLIANCE\s+CERTIFICATE', caseSensitive: false),
      RegExp(r'CERTIFICATE\s+OF\s+REGISTRY', caseSensitive: false),
      RegExp(r'CERTIFICATE\s+OF\s+OWNERSHIP', caseSensitive: false),
      RegExp(r'TONNAGE\s+MEASUREMENT', caseSensitive: false),
      RegExp(r'(?:certificate\s+type|type\s+of\s+certificate)[\s:]*([^\n\r]+)', caseSensitive: false),
    ];

    for (var pattern in certificateTypePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        certificateData['certificateType'] = match.groupCount > 0 ? match.group(1)?.trim() : match.group(0)?.trim();
        print('Found certificateType: ${certificateData['certificateType']}');
        break;
      }
    }

    // Certificate number patterns (prioritize CPC patterns)
    final certNumberPatterns = [
      RegExp(r'CPC\s+No\.\s*([0-9]+)', caseSensitive: false),
      RegExp(r'CPC-([0-9]+)', caseSensitive: false),
      RegExp(r'(?:certificate\s+of\s+public\s+convenience\s+no|cpc\s+no)[\s:]*([0-9]+)', caseSensitive: false),
      RegExp(r'(?:certificate\s+number|cert\s+no|certificate\s+no)[\s:]*([A-Z0-9\-]+)', caseSensitive: false),
      RegExp(r'Ref\.\s+([0-9\-]+)', caseSensitive: false),
      RegExp(r'Case\s+No\.\s+([A-Z0-9\-]+)', caseSensitive: false),
    ];

    for (var pattern in certNumberPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final number = match.group(1)!.trim();
        if (number != 'WNL' && number != 'MNL') {
          certificateData['certificateNumber'] = number;
          print('Found certificateNumber: ${certificateData['certificateNumber']}');
          break;
        }
      }
    }

    // Date issued patterns
    final dateIssuedPatterns = [
      RegExp(r'(?:dated|issued\s+on|granted\s+on|decision\s+dated)\s+(\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4})', caseSensitive: false),
      RegExp(r'decision\s+dated\s+(\d{1,2}\s+\w+\s+\d{4})', caseSensitive: false),
      RegExp(r'(?:date\s+issued|issued\s+date|issued\s+on)[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})', caseSensitive: false),
      RegExp(r'(?:issued)[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})', caseSensitive: false),
    ];

    for (var pattern in dateIssuedPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final date = _normalizeDate(match.group(1)!.trim());
        if (date.isNotEmpty) {
          certificateData['dateIssued'] = date;
          print('Found dateIssued: ${certificateData['dateIssued']}');
          break;
        }
      }
    }

    // Expiry date patterns
    final expiryDatePatterns = [
      RegExp(r'(?:valid\s+until|expires?\s+on|expiry\s+date|until\s+)(\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4})', caseSensitive: false),
      RegExp(r'to\s+operate\s+the\s+ships[^.]*?(\d{1,2}\s+\w+\s+\d{4})', caseSensitive: false),
      RegExp(r'(?:expiry\s+date|expires\s+on|valid\s+until|expiry)[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})', caseSensitive: false),
      RegExp(r'(?:valid\s+until)[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})', caseSensitive: false),
    ];

    for (var pattern in expiryDatePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final date = _normalizeDate(match.group(1)!.trim());
        if (date.isNotEmpty) {
          certificateData['dateExpiry'] = date;
          print('Found dateExpiry: ${certificateData['dateExpiry']}');
          break;
        }
      }
    }

    // Issuing authority
    final authorityPatterns = [
      RegExp(r'(?:issuing\s+authority|issued\s+by|authority)[\s:]*([^\n\r]+)', caseSensitive: false),
      RegExp(r'MARITIME\s+INDUSTRY\s+AUTHORITY', caseSensitive: false),
      RegExp(r'BY\s+AUTHORITY\s+OF\s+THE\s+MARINA\s+BOARD', caseSensitive: false),
    ];

    for (var pattern in authorityPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        certificateData['issuingAuthority'] = match.groupCount > 0 
          ? match.group(1)?.trim() 
          : (match.group(0)?.contains('MARINA') == true ? 'MARITIME INDUSTRY AUTHORITY' : match.group(0)?.trim());
        print('Found issuingAuthority: ${certificateData['issuingAuthority']}');
        break;
      }
    }

    // Certificate holder
    final holderPattern = RegExp(r'This\s+Certificate\s+is\s+hereby\s+given\s+to[\s:]*([^\n\r,]+)', caseSensitive: false);
    final holderMatch = holderPattern.firstMatch(text);
    if (holderMatch != null && holderMatch.group(1) != null) {
      certificateData['certificateHolder'] = holderMatch.group(1)!.trim();
      print('Found certificateHolder: ${certificateData['certificateHolder']}');
    }

    return certificateData;
  }

  // Extract crew/seafarer data from OCR text
  Map<String, dynamic> extractCrewData(String text) {
    print('Extracting crew data from text...');
    final crewData = <String, dynamic>{};

    // Name patterns (SIRB and general)
    final namePatterns = [
      RegExp(r'(?:NAME)[\s:]*([A-Z]{2,}\s+[A-Z]\.\s+[A-Z]{2,})', caseSensitive: false),
      RegExp(r'(?:NAME)[\s:]*([A-Z]{2,}\s+[A-Z]{2,}\s+[A-Z]\.\s+[A-Z]{2,})', caseSensitive: false),
      RegExp(r'([A-Z]{2,}\s+[A-Z]\.\s+[A-Z]{2,})', caseSensitive: false),
      RegExp(r'(?:name|full\s+name|officer\s+name)[\s:]*([A-Z][A-Za-z\s,\.]+?)(?:\n|certificate|date|position|rank|expiry)', caseSensitive: false),
      RegExp(r'(?:name)[\s:]*([A-Z][A-Za-z\s,\.]+)', caseSensitive: false),
    ];

    for (var pattern in namePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        crewData['name'] = _cleanName(match.group(1)!.trim());
        print('Found name: ${crewData['name']}');
        break;
      }
    }

    // Position patterns
    final positionPattern = RegExp(
      r'(?:MASTER|CHIEF\s+OFFICER|2ND\s+OFFICER|3RD\s+OFFICER|CHIEF\s+ENGINEER|2ND\s+MARINE\s+ENGINEER|3RD\s+MARINE\s+ENGINEER|4TH\s+MARINE\s+ENGINEER|ABLE\s+SEAMAN|OILER|BOSUN|ORDINARY\s+SEAMAN|RADIO\s+OPERATOR|CRANE\s+OPERATOR|DECK\s+CADET|ENGINE\s+CADET|APPRENTICE\s+MATE|CHIEF\s+COOK)',
      caseSensitive: false
    );
    final positionMatch = positionPattern.firstMatch(text);
    if (positionMatch != null) {
      crewData['position'] = positionMatch.group(0)!.trim();
      print('Found position: ${crewData['position']}');
    }

    // Certificate number (SIRB format)
    final certNumberPatterns = [
      RegExp(r'(\d{4}[-:]\d{2}[-:]\d{4}[-:]\d{6})', caseSensitive: false),
      RegExp(r'(?:certificate\s+number|cert\s+no|certificate\s+no)[\s:]*([A-Z0-9\-]+)', caseSensitive: false),
      RegExp(r'(?:license\s+number|license\s+no)[\s:]*([A-Z0-9\-]+)', caseSensitive: false),
    ];

    for (var pattern in certNumberPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        crewData['certificateNumber'] = match.groupCount > 0 ? match.group(1)?.trim() : match.group(0)?.trim();
        print('Found certificateNumber: ${crewData['certificateNumber']}');
        break;
      }
    }

    // Expiry date (SIRB format: "VALID UNTIL: Feb 6, 2028")
    final expiryDatePatterns = [
      RegExp(r'(?:VALID\s+UNTIL)[\s:]*(\w{3}\s+\d{1,2},\s+\d{4})', caseSensitive: false),
      RegExp(r'(?:VALID\s+UNTIL)\s+(\w{3}\s+\d{1,2},\s+\d{4})', caseSensitive: false),
      RegExp(r'(?:expiry|expires|valid\s+until|validity)[\s:]*(\d{1,2}[-\/\.]\d{1,2}[-\/\.]\d{2,4})', caseSensitive: false),
      RegExp(r'(\d{1,2}\s+(?:Feb|Jan|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4})', caseSensitive: false),
    ];

    for (var pattern in expiryDatePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final date = _normalizeDate(match.group(1)!.trim());
        if (date.isNotEmpty) {
          crewData['expiryDate'] = date;
          print('Found expiryDate: ${crewData['expiryDate']}');
          break;
        }
      }
    }

    return crewData;
  }

  // Extract COC (Certificate of Competency) data
  Map<String, dynamic> extractCOCData(String text) {
    print('Extracting COC data from text...');
    final cocData = <String, dynamic>{};

    // Name patterns for COC
    final namePatterns = [
      RegExp(r'(?:certifies\s+that)\s+([A-Z][A-Za-z\s]+?)(?:\s+has\s+been\s+found\s+duly\s+qualified)', caseSensitive: false),
      RegExp(r'([A-Z][A-Za-z]+\s+[A-Z][A-Za-z]+\s+[A-Z][A-Za-z]+)', caseSensitive: false),
      RegExp(r'([A-Z][A-Za-z]+\s+[A-Z]\.\s+[A-Z][A-Za-z]+)', caseSensitive: false),
    ];

    for (var pattern in namePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        cocData['name'] = _cleanName(match.group(1)!.trim());
        print('Found COC name: ${cocData['name']}');
        break;
      }
    }

    // Position/Capacity
    final positionPattern = RegExp(r'(?:OFFICER\s+IN\s+CHARGE\s+OF\s+A\s+NAVIGATIONAL\s+WATCH|CHIEF\s+ENGINEER\s+on\s+ships)', caseSensitive: false);
    final positionMatch = positionPattern.firstMatch(text);
    if (positionMatch != null) {
      cocData['position'] = positionMatch.group(0)!.trim();
      print('Found COC position: ${cocData['position']}');
    }

    // Certificate number
    final certNumberPattern = RegExp(r'(?:certificate\s+no\.?)[\s:]*([A-Z]{2,4}\d{12,15})', caseSensitive: false);
    final certMatch = certNumberPattern.firstMatch(text);
    if (certMatch != null && certMatch.group(1) != null) {
      cocData['certificateNumber'] = certMatch.group(1)!.trim();
      print('Found COC certificateNumber: ${cocData['certificateNumber']}');
    }

    // Expiry date (COC format: "Date of Expiry: August 25, 2027")
    final expiryPattern = RegExp(r'(?:Date\s+of\s+Expiry)[\s:]*([A-Za-z]+\s+\d{1,2},\s+\d{4})', caseSensitive: false);
    final expiryMatch = expiryPattern.firstMatch(text);
    if (expiryMatch != null && expiryMatch.group(1) != null) {
      final date = _normalizeDate(expiryMatch.group(1)!.trim());
      if (date.isNotEmpty) {
        cocData['dateExpiry'] = date;
        print('Found COC dateExpiry: ${cocData['dateExpiry']}');
      }
    }

    return cocData;
  }

  // Extract vessel data from OCR text
  Map<String, dynamic> extractVesselData(String text) {
    print('Extracting vessel data from text...');
    final vesselData = <String, dynamic>{};

    // Vessel name
    final vesselMatch = RegExp(r'vessel\s+name\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(text);
    if (vesselMatch != null && vesselMatch.group(1) != null) {
      vesselData['vesselName'] = vesselMatch.group(1)!.trim();
    }

    // IMO number
    final imoMatch = RegExp(r'imo\s+number\s*:\s*(\d{7})', caseSensitive: false).firstMatch(text);
    if (imoMatch != null && imoMatch.group(1) != null) {
      vesselData['imoNumber'] = imoMatch.group(1)!.trim();
    }

    return vesselData;
  }

  // Normalize date format
  String _normalizeDate(String dateString) {
    if (dateString.isEmpty) return '';
    
    print('Normalizing date: $dateString');
    
    final monthNames = {
      'january': '01', 'jan': '01',
      'february': '02', 'feb': '02',
      'march': '03', 'mar': '03',
      'april': '04', 'apr': '04',
      'may': '05',
      'june': '06', 'jun': '06',
      'july': '07', 'jul': '07',
      'august': '08', 'aug': '08',
      'september': '09', 'sep': '09',
      'october': '10', 'oct': '10',
      'november': '11', 'nov': '11',
      'december': '12', 'dec': '12',
    };

    // Handle format: "Feb 6, 2028" or "Feb 6,2028"
    final monthAbbrPattern = RegExp(r'(\w{3})\s+(\d{1,2}),\s*(\d{4})', caseSensitive: false);
    final monthAbbrMatch = monthAbbrPattern.firstMatch(dateString);
    if (monthAbbrMatch != null) {
      final month = monthNames[monthAbbrMatch.group(1)!.toLowerCase()] ?? '01';
      final day = monthAbbrMatch.group(2)!.padLeft(2, '0');
      final year = monthAbbrMatch.group(3)!;
      return '$year-$month-$day';
    }

    // Handle format: "6 Feb 2028"
    final dayMonthPattern = RegExp(r'(\d{1,2})\s+(\w{3})\s+(\d{4})', caseSensitive: false);
    final dayMonthMatch = dayMonthPattern.firstMatch(dateString);
    if (dayMonthMatch != null) {
      final day = dayMonthMatch.group(1)!.padLeft(2, '0');
      final month = monthNames[dayMonthMatch.group(2)!.toLowerCase()] ?? '01';
      final year = dayMonthMatch.group(3)!;
      return '$year-$month-$day';
    }

    // Handle format: "DD/MM/YYYY" or "MM/DD/YYYY"
    final datePattern = RegExp(r'(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})');
    final dateMatch = datePattern.firstMatch(dateString);
    if (dateMatch != null) {
      var day = dateMatch.group(1)!.padLeft(2, '0');
      var month = dateMatch.group(2)!.padLeft(2, '0');
      var year = dateMatch.group(3)!;
      if (year.length == 2) {
        year = int.parse(year) > 50 ? '19$year' : '20$year';
      }
      // Assume DD/MM/YYYY for Philippine dates
      return '$year-$month-$day';
    }

    return dateString;
  }

  // Clean name to remove OCR artifacts
  String _cleanName(String name) {
    if (name.isEmpty) return name;
    
    // Remove common OCR artifacts
    var cleaned = name
        .replaceAll(RegExp(r'[|\[\]{}()]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Capitalize properly
    final words = cleaned.split(' ');
    cleaned = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    
    return cleaned;
  }
}

// Export singleton instance
final dataExtractionService = DataExtractionService();
