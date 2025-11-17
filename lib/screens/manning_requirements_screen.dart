import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ManningRequirementsResult {
  const ManningRequirementsResult({
    required this.deckDepartment,
    required this.engineDepartment,
    required this.deckFiles,
    required this.engineFiles,
    required this.authorizedCrew,
    required this.othersNumber,
  });

  final List<Map<String, dynamic>> deckDepartment;
  final List<Map<String, dynamic>> engineDepartment;
  final Map<String, String> deckFiles;
  final Map<String, String> engineFiles;
  final String authorizedCrew;
  final String othersNumber;
}

class ManningRequirementsScreen extends StatefulWidget {
  const ManningRequirementsScreen({
    super.key,
    required this.initialDeckDepartment,
    required this.initialEngineDepartment,
    required this.initialDeckFiles,
    required this.initialEngineFiles,
    required this.initialAuthorizedCrew,
    required this.initialOthersNumber,
    required this.positions,
    required this.licenses,
  });

  final List<Map<String, dynamic>> initialDeckDepartment;
  final List<Map<String, dynamic>> initialEngineDepartment;
  final Map<String, String> initialDeckFiles;
  final Map<String, String> initialEngineFiles;
  final String initialAuthorizedCrew;
  final String initialOthersNumber;
  final List<String> positions;
  final List<String> licenses;

  @override
  State<ManningRequirementsScreen> createState() =>
      _ManningRequirementsScreenState();
}

class _ManningRow {
  _ManningRow({
    required this.id,
    required this.position,
    required this.license,
    required this.number,
    this.isDefault = false,
    this.isLicenseEditable = true,
  });

  final int id;
  String position;
  String license;
  String number;
  bool isDefault;
  bool isLicenseEditable;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'position': position,
      'license': license,
      'number': number,
    };
  }
}

class _ManningRequirementsScreenState
    extends State<ManningRequirementsScreen> {
  late List<_ManningRow> _deckRows;
  late List<_ManningRow> _engineRows;
  late Map<String, String> _deckFiles;
  late Map<String, String> _engineFiles;
  late TextEditingController _authorizedCrewController;
  late TextEditingController _othersNumberController;

  final List<_ManningRow> _deckDefaults = [
    _ManningRow(
      id: -1,
      position: 'MASTER',
      license: '',
      number: '1',
      isDefault: true,
      isLicenseEditable: true,
    ),
    _ManningRow(
      id: -2,
      position: 'CHIEF OFFICER',
      license: '',
      number: '1',
      isDefault: true,
      isLicenseEditable: true,
    ),
    _ManningRow(
      id: -3,
      position: 'RATINGS',
      license: 'N.A',
      number: '3',
      isDefault: true,
      isLicenseEditable: false,
    ),
  ];

  final List<_ManningRow> _engineDefaults = [
    _ManningRow(
      id: -11,
      position: 'CHIEF ENGINE OFFICER',
      license: '',
      number: '1',
      isDefault: true,
      isLicenseEditable: true,
    ),
    _ManningRow(
      id: -12,
      position: 'ENGINE OFFICER',
      license: '',
      number: '1',
      isDefault: true,
      isLicenseEditable: true,
    ),
    _ManningRow(
      id: -13,
      position: 'RATINGS',
      license: 'N.A',
      number: '3',
      isDefault: true,
      isLicenseEditable: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _deckRows = widget.initialDeckDepartment
        .map((entry) => _ManningRow(
              id: _parseId(entry['id']),
              position: _normalizePosition(entry['position']?.toString() ?? ''),
              license: _normalizeLicense(entry['license']?.toString() ?? ''),
              number: entry['number']?.toString() ?? '0',
              isDefault: false,
              isLicenseEditable: true,
            ))
        .toList();
    _engineRows = widget.initialEngineDepartment
        .map((entry) => _ManningRow(
              id: _parseId(entry['id']),
              position: _normalizePosition(entry['position']?.toString() ?? ''),
              license: _normalizeLicense(entry['license']?.toString() ?? ''),
              number: entry['number']?.toString() ?? '0',
              isDefault: false,
              isLicenseEditable: true,
            ))
        .toList();

    _deckFiles = Map<String, String>.from(widget.initialDeckFiles);
    _engineFiles = Map<String, String>.from(widget.initialEngineFiles);

    _authorizedCrewController =
        TextEditingController(text: widget.initialAuthorizedCrew);
    _othersNumberController =
        TextEditingController(text: widget.initialOthersNumber);

    _ensureDefaultRows();
  }

  @override
  void dispose() {
    _authorizedCrewController.dispose();
    _othersNumberController.dispose();
    super.dispose();
  }

  int _parseId(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? _generateTempId();
    }
    return _generateTempId();
  }

  int _generateTempId() => DateTime.now().millisecondsSinceEpoch + Random().nextInt(999);

  void _ensureDefaultRows() {
    _addMissingDefaults(_deckRows, _deckDefaults);
    _addMissingDefaults(_engineRows, _engineDefaults);
  }

  void _addMissingDefaults(List<_ManningRow> target, List<_ManningRow> defaults) {
    for (final def in defaults) {
      final index = target.indexWhere(
        (row) => row.position.toUpperCase() == def.position.toUpperCase(),
      );
      if (index == -1) {
        target.add(
          _ManningRow(
            id: _generateTempId(),
            position: def.position,
            license: def.license,
            number: def.number,
            isDefault: true,
            isLicenseEditable: def.isLicenseEditable,
          ),
        );
      } else {
        final existing = target[index];
        existing.isDefault = true;
        existing.isLicenseEditable = def.isLicenseEditable;
        if (!def.isLicenseEditable) {
          existing.license = def.license;
        }
      }
    }

    target.sort((a, b) {
      final aIndex = defaults.indexWhere(
          (def) => def.position.toUpperCase() == a.position.toUpperCase());
      final bIndex = defaults.indexWhere(
          (def) => def.position.toUpperCase() == b.position.toUpperCase());
      final aScore = aIndex == -1 ? 1000 + a.position.hashCode.abs() : aIndex;
      final bScore = bIndex == -1 ? 1000 + b.position.hashCode.abs() : bIndex;
      return aScore.compareTo(bScore);
    });
  }

  void _addRow({required bool isDeck}) async {
    String? selectedPosition;
    String? selectedLicense;
    String number = '1';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Add ${isDeck ? 'Deck' : 'Engine'} Position',
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        DropdownButtonFormField<String>(
                          value: selectedPosition,
                          isExpanded: true,
                          onChanged: (value) {
                            setDialogState(() => selectedPosition = value);
                          },
                          items: widget.positions
                              .toSet() // Remove duplicates
                              .map(
                                (pos) => DropdownMenuItem(
                                  value: pos,
                                  child: Text(
                                    pos,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'Position *',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          selectedItemBuilder: (context) => widget.positions
                              .toSet() // Remove duplicates
                              .map(
                                (pos) => Text(
                                  pos,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedLicense,
                          isExpanded: true,
                          onChanged: (value) {
                            setDialogState(() => selectedLicense = value);
                          },
                          items: widget.licenses
                              .toSet() // Remove duplicates
                              .map(
                                (lic) => DropdownMenuItem(
                                  value: lic,
                                  child: Text(
                                    lic,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'License *',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          selectedItemBuilder: (context) => widget.licenses
                              .map(
                                (lic) => Text(
                                  lic,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: number,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (value) {
                            setDialogState(() => number = value.isEmpty ? '0' : value);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Number *',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if ((selectedPosition ?? '').isEmpty ||
                        (selectedLicense ?? '').isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill out all required fields.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      final newRow = _ManningRow(
                        id: _generateTempId(),
                        position: selectedPosition!,
                        license: selectedLicense!,
                        number: number,
                        isDefault: false,
                        isLicenseEditable: true,
                      );
                      if (isDeck) {
                        _deckRows.add(newRow);
                      } else {
                        _engineRows.add(newRow);
                      }
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeRow({required bool isDeck, required int id}) {
    setState(() {
      if (isDeck) {
        _deckRows.removeWhere((row) => row.id == id && !row.isDefault);
        _deckFiles.remove(id.toString());
      } else {
        _engineRows.removeWhere((row) => row.id == id && !row.isDefault);
        _engineFiles.remove(id.toString());
      }
    });
  }

  int _calculateTotal(List<_ManningRow> rows) {
    return rows.fold<int>(0, (sum, row) {
      final value = int.tryParse(row.number) ?? 0;
      return sum + value;
    });
  }

  Future<void> _handleSave() async {
    if (_deckRows.isEmpty && _engineRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one deck or engine position.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final deckMaps = _deckRows.map((row) => row.toMap()).toList();
    final engineMaps = _engineRows.map((row) => row.toMap()).toList();

    Navigator.of(context).pop(
      ManningRequirementsResult(
        deckDepartment: deckMaps,
        engineDepartment: engineMaps,
        deckFiles: _deckFiles,
        engineFiles: _engineFiles,
        authorizedCrew: _authorizedCrewController.text,
        othersNumber: _othersNumberController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        title: const Text(
          'Manning Requirements',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(theme),
              const SizedBox(height: 20),
              _buildDepartmentSection(
                title: 'Deck Department',
                highlightColor: const Color(0xFF153E90),
                rows: _deckRows,
                files: _deckFiles,
                onAddPressed: () => _addRow(isDeck: true),
                onRemovePressed: (id) => _removeRow(isDeck: true, id: id),
              ),
              const SizedBox(height: 24),
              _buildDepartmentSection(
                title: 'Engine Department',
                highlightColor: const Color(0xFF1F2D3D),
                rows: _engineRows,
                files: _engineFiles,
                onAddPressed: () => _addRow(isDeck: false),
                onRemovePressed: (id) => _removeRow(isDeck: false, id: id),
              ),
              const SizedBox(height: 24),
              _buildPsscSection(theme),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _handleSave,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF2F7BFF),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF3FF), Color(0xFFFAFBFF)],
        ),
        border: Border.all(color: const Color(0xFFBAC6EF).withOpacity(0.45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'MANNING REQUIREMENTS (MSMC)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Container(
            height: 2,
            width: 84,
            decoration: BoxDecoration(
              color: const Color(0xFF4C6EF5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Marina Circular No. 2012-06',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentSection({
    required String title,
    required Color highlightColor,
    required List<_ManningRow> rows,
    required Map<String, String> files,
    required VoidCallback onAddPressed,
    required void Function(int id) onRemovePressed,
  }) {
    final borderRadius = BorderRadius.circular(24);
    final headerColor = const Color(0xFF1B2330);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: borderRadius.topLeft,
                topRight: borderRadius.topRight,
              ),
              color: Colors.white,
            ),
            child: Column(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: const Color(0xFF1F2D3D),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 3,
                  width: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        highlightColor.withOpacity(0.15),
                        highlightColor,
                        highlightColor.withOpacity(0.15),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text(
                    'POSITION',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    'LICENSE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(
                    'NUMBER',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              child: Text(
                'No positions yet. Use the button below to add your first entry.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...rows.map(
              (row) => _buildManningEntryCard(
                row: row,
                highlightColor: highlightColor,
                onRemovePressed: onRemovePressed,
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE0E7FF)),
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  '+ Add ${title.contains('Deck') ? 'Deck' : 'Engine'} Position',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: highlightColor,
                  side: BorderSide(color: highlightColor, width: 1.5),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  highlightColor.withOpacity(0.95),
                  highlightColor,
                ],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: borderRadius.bottomLeft,
                bottomRight: borderRadius.bottomRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _calculateTotal(rows).toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManningEntryCard({
    required _ManningRow row,
    required Color highlightColor,
    required void Function(int id) onRemovePressed,
  }) {
    final isDefault = row.isDefault;
    final borderColor =
        isDefault ? highlightColor.withOpacity(0.25) : const Color(0xFFE4E8F1);
    final backgroundColor =
        isDefault ? highlightColor.withOpacity(0.05) : Colors.white;
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey[700],
      letterSpacing: 0.2,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isDefault ? '${row.position} (Default)' : row.position,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDefault ? highlightColor : Colors.black87,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (!isDefault)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () => onRemovePressed(row.id),
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Position', style: labelStyle),
          const SizedBox(height: 6),
          if (isDefault)
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                row.position,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: row.position.isEmpty || !widget.positions.contains(row.position)
                  ? null
                  : row.position,
              isExpanded: true,
              items: widget.positions
                  .toSet() // Remove duplicates
                  .map(
                    (pos) => DropdownMenuItem(
                      value: pos,
                      child: Text(
                        pos,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => row.position = (value ?? '').trim(),
              ),
              decoration: _tableInputDecoration()
                  .copyWith(labelText: 'Position'),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              selectedItemBuilder: (context) => widget.positions
                  .toSet() // Remove duplicates
                  .map(
                    (pos) => Text(
                      pos,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Text('License', style: labelStyle),
          const SizedBox(height: 6),
          row.isLicenseEditable
              ? DropdownButtonFormField<String>(
                  value: row.license.isEmpty || !widget.licenses.contains(row.license)
                      ? null
                      : row.license,
                  isExpanded: true,
                  items: widget.licenses
                      .toSet() // Remove duplicates
                      .map(
                        (lic) => DropdownMenuItem(
                          value: lic,
                          child: Text(
                            lic,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => row.license = (value ?? '').trim(),
                  ),
                  decoration: _tableInputDecoration()
                      .copyWith(labelText: 'License'),
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  selectedItemBuilder: (context) => widget.licenses
                      .toSet() // Remove duplicates
                      .map(
                        (lic) => Text(
                          lic,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                      .toList(),
                )
              : Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    row.license,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
          const SizedBox(height: 12),
          Text('Number', style: labelStyle),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: row.number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) =>
                row.number = value.isEmpty ? '0' : value,
            decoration: _tableInputDecoration().copyWith(labelText: 'Number'),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildPsscSection(ThemeData theme) {
    final accentColor = const Color(0xFF1B8A5A);
    final authorized =
        int.tryParse(_authorizedCrewController.text.trim()) ?? 0;
    final others = int.tryParse(_othersNumberController.text.trim()) ?? 0;
    final total = authorized + others;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                Text(
                  'PSSC (Total Persons Onboard)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 3,
                  width: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withOpacity(0.15),
                        accentColor,
                        accentColor.withOpacity(0.15),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                _buildPsscInputRow(
                  label: 'Authorized Crew',
                  controller: _authorizedCrewController,
                  accentColor: accentColor,
                ),
                const SizedBox(height: 16),
                _buildPsscInputRow(
                  label: 'Others (Support)',
                  controller: _othersNumberController,
                  accentColor: accentColor,
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.95),
                  accentColor,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        total.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPsscInputRow({
    required String label,
    required TextEditingController controller,
    required Color accentColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2D3D),
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _tableInputDecoration(),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  InputDecoration _tableInputDecoration() {
    return InputDecoration(
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E8F1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E8F1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4C6EF5)),
      ),
    );
  }

  /// Normalizes position value to match exact value in widget.positions list
  /// Handles case differences between stored data and dropdown items
  String _normalizePosition(String positionValue) {
    if (positionValue.isEmpty) {
      return '';
    }

    // First try exact match (case-sensitive)
    if (widget.positions.contains(positionValue)) {
      return positionValue;
    }

    // Try case-insensitive match
    final normalizedValue = positionValue.toUpperCase().trim();
    for (final pos in widget.positions) {
      if (pos.toUpperCase().trim() == normalizedValue) {
        return pos; // Return the exact value from positions list
      }
    }

    // If no match found, return original value (will show as null in dropdown)
    return positionValue;
  }

  /// Normalizes license value to match exact value in widget.licenses list
  /// Handles case differences and variations between stored data and dropdown items
  String _normalizeLicense(String licenseValue) {
    if (licenseValue.isEmpty || licenseValue == 'N.A' || licenseValue == 'N/A') {
      return licenseValue; // Keep special values as-is
    }

    // First try exact match (case-sensitive)
    if (widget.licenses.contains(licenseValue)) {
      return licenseValue;
    }

    // Try case-insensitive match
    final normalizedValue = licenseValue.toUpperCase().trim();
    for (final lic in widget.licenses) {
      if (lic.toUpperCase().trim() == normalizedValue) {
        return lic; // Return the exact value from licenses list
      }
    }

    // Handle common variations (e.g., "BOAT CAPTAIN 3" might be stored but not in list)
    // Try to find closest match (e.g., "BOAT CAPTAIN 3" -> "BOAT CAPTAIN 2" or "BOAT CAPTAIN 1")
    if (normalizedValue.contains('BOAT CAPTAIN')) {
      // If it's a boat captain variation, try to match to existing boat captain licenses
      for (final lic in widget.licenses) {
        if (lic.toUpperCase().contains('BOAT CAPTAIN')) {
          return lic; // Return the first matching boat captain license
        }
      }
    }

    // If no match found, return empty string (will show as null in dropdown)
    return '';
  }
}

