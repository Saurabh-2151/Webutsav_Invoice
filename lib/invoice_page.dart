import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart' as printing;
import 'package:file_saver/file_saver.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  // Editable fields
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _invoiceNo = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  // Parties
  final TextEditingController _billedByName = TextEditingController();
  final TextEditingController _billedByAddress = TextEditingController();
  final TextEditingController _billedByEmail = TextEditingController();
  final TextEditingController _gstin = TextEditingController();
  final TextEditingController _pan = TextEditingController();

  final TextEditingController _billedToName = TextEditingController();
  final TextEditingController _billedToAddress = TextEditingController();
  final TextEditingController _billedToGstin = TextEditingController();
  final TextEditingController _billedToMobile = TextEditingController();
  final TextEditingController _billedToEmail = TextEditingController();

  // Bank/UPI
  final TextEditingController _accountName = TextEditingController();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _ifsc = TextEditingController();
  final TextEditingController _accountType = TextEditingController();
  final TextEditingController _bank = TextEditingController();
  final TextEditingController _upiId = TextEditingController();
  // Terms & Conditions (user-provided)
  final TextEditingController _terms = TextEditingController();

  // SharedPreferences keys for persistence (only requested sections)
  static const String _kBilledByName = 'billed_by_name';
  static const String _kBilledByAddress = 'billed_by_address';
  static const String _kBilledByEmail = 'billed_by_email';
  static const String _kBilledByGstin = 'billed_by_gstin';
  static const String _kBilledByPan = 'billed_by_pan';

  static const String _kAccountName = 'bank_account_name';
  static const String _kAccountNumber = 'bank_account_number';
  static const String _kIfsc = 'bank_ifsc';
  static const String _kAccountType = 'bank_account_type';
  static const String _kBank = 'bank_name';
  static const String _kUpiId = 'upi_id';

  static const String _kTerms = 'invoice_terms';

  @override
  void initState() {
    super.initState();
    _loadPersistedFields();
  }

  Future<void> _loadPersistedFields() async {
    final prefs = await SharedPreferences.getInstance();
    // Billed By
    _billedByName.text = prefs.getString(_kBilledByName) ?? '';
    _billedByAddress.text = prefs.getString(_kBilledByAddress) ?? '';
    _billedByEmail.text = prefs.getString(_kBilledByEmail) ?? '';
    _gstin.text = prefs.getString(_kBilledByGstin) ?? '';
    _pan.text = prefs.getString(_kBilledByPan) ?? '';
    // Bank/UPI
    _accountName.text = prefs.getString(_kAccountName) ?? '';
    _accountNumber.text = prefs.getString(_kAccountNumber) ?? '';
    _ifsc.text = prefs.getString(_kIfsc) ?? '';
    _accountType.text = prefs.getString(_kAccountType) ?? '';
    _bank.text = prefs.getString(_kBank) ?? '';
    _upiId.text = prefs.getString(_kUpiId) ?? '';
    // Terms
    _terms.text = prefs.getString(_kTerms) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveField(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  // Items list
  final List<_InvoiceItem> _items = [];

  final _inCurrency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  // Total amount from all items
  double get _amount => _items.fold(0.0, (sum, it) => sum + it.amount);
  // Taxes (flat 18% = CGST 9% + SGST 9%)
  double get _subTotal => _amount;
  double get _cgst => _subTotal * 0.09;
  double get _sgst => _subTotal * 0.09;
  double get _grandTotal => _subTotal + _cgst + _sgst;

  Future<Uint8List> _generatePdfBytes() async {
    // Load multiple font weights (Roboto supports 100–900) for manual weight control
    final f100 = await printing.PdfGoogleFonts.robotoThin();
    final f300 = await printing.PdfGoogleFonts.robotoLight();
    final f400 = await printing.PdfGoogleFonts.robotoRegular();
    final f500 = await printing.PdfGoogleFonts.robotoMedium();
    final f700 = await printing.PdfGoogleFonts.robotoBold();
    final f900 = await printing.PdfGoogleFonts.robotoBlack();

    // Helper to choose a specific font by numeric weight
    pw.Font fontForWeight(int weight) {
      if (weight >= 900) return f900;
      if (weight >= 700) return f700;
      if (weight >= 500) return f500;
      if (weight >= 400) return f400;
      if (weight >= 300) return f300;
      return f100;
    }

    // Use a baseline theme; specific widgets can override with exact fonts
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: f400, bold: f700),
    );
    final formatCurrency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    // Load logo if available
    final logoImage = await _loadLogoImage();
    // Pre-generate UPI QR image for PDF embedding (pdf widgets do not support async builders)
    pw.ImageProvider? upiQrImage;
    if (_upiId.text.trim().isNotEmpty) {
      final qrData =
          'upi://pay?pa=${_upiId.text.trim()}&pn=${Uri.encodeComponent(_accountName.text.trim().isEmpty ? 'Payee' : _accountName.text.trim())}&am=${_grandTotal.toStringAsFixed(2)}&cu=INR';
      try {
        upiQrImage = await _generateQrImage(qrData);
      } catch (_) {
        upiQrImage = null;
      }
    }

    pw.Widget kv(String k, String v) => pw.Container(
      width: 260,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 90,
            child: pw.Text(k, style: pw.TextStyle(font: fontForWeight(700))),
          ),
          pw.SizedBox(width: 2),
          pw.Expanded(
            child: pw.Text(v, style: pw.TextStyle(font: fontForWeight(300))),
          ),
        ],
      ),
    );

    final itemsRows = <List<String>>[
      [
        '',
        'Item',
        'GST Rate',
        'Qty',
        'Rate',
        'Amount',
        'CGST',
        'SGST',
        'Total',
      ],
      ...List.generate(_items.length, (i) {
        final it = _items[i];
        final qty = it.qty % 1 == 0
            ? it.qty.toStringAsFixed(0)
            : it.qty.toString();
        final cgst = it.amount * 0.09;
        final sgst = it.amount * 0.09;
        final total = it.amount + cgst + sgst;
        return [
          '${i + 1}',
          it.name,
          '18%',
          qty,
          formatCurrency.format(it.rate),
          formatCurrency.format(it.amount),
          formatCurrency.format(cgst),
          formatCurrency.format(sgst),
          formatCurrency.format(total),
        ];
      }),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Center(
            child: pw.Text(
              'This is an electronically generated document, no signature is required.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                color: pdf.PdfColors.grey,
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ),
        build: (context) => [
          // Header Section with Logo
          pw.Container(
            width: pdf.PdfPageFormat.a4.width - 56,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 200,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 26,
                          font: fontForWeight(900),
                          color: pdf.PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      kv('Invoice No #', _invoiceNo.text.trim()),
                      kv(
                        'Invoice Date',
                        DateFormat('MMM d, y').format(_invoiceDate),
                      ),
                      kv('Due Date', DateFormat('MMM d, y').format(_dueDate)),
                    ],
                  ),
                ),
                if (logoImage != null)
                  pw.Container(
                    width: 120,
                    height: 80,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: pdf.PdfColors.grey300, thickness: 1),
          pw.SizedBox(height: 12),

          // Billed By and Billed To
          pw.Container(
            width: pdf.PdfPageFormat.a4.width - 56,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Billed By',
                        style: pw.TextStyle(
                          font: fontForWeight(900),
                          color: pdf.PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        _billedByName.text.trim(),
                        style: pw.TextStyle(font: fontForWeight(700)),
                      ),
                      if (_billedByAddress.text.trim().isNotEmpty)
                        pw.Text(_billedByAddress.text.trim()),
                      if (_gstin.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'GSTIN',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _gstin.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_pan.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'PAN',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _pan.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_billedByEmail.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Email',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _billedByEmail.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Billed To',
                        style: pw.TextStyle(
                          font: fontForWeight(900),
                          color: pdf.PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        _billedToName.text.trim(),
                        style: pw.TextStyle(font: fontForWeight(700)),
                      ),
                      if (_billedToAddress.text.trim().isNotEmpty)
                        pw.Text(_billedToAddress.text.trim()),
                      if (_billedToGstin.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'GSTIN',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _billedToGstin.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_billedToMobile.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Mobile',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _billedToMobile.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_billedToEmail.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Email',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              _billedToEmail.text.trim(),
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Items Table
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(
              color: pdf.PdfColors.deepPurple400,
            ),
            headerStyle: pw.TextStyle(
              font: fontForWeight(600),
              color: pdf.PdfColors.white,
            ),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 10),
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: pdf.PdfColors.grey300,
                width: 0.5,
              ),
              verticalInside: pw.BorderSide(
                color: pdf.PdfColors.grey300,
                width: 0.5,
              ),
              top: const pw.BorderSide(
                color: pdf.PdfColors.grey600,
                width: 0.8,
              ),
              bottom: const pw.BorderSide(
                color: pdf.PdfColors.grey600,
                width: 0.8,
              ),
              left: const pw.BorderSide(
                color: pdf.PdfColors.grey600,
                width: 0.8,
              ),
              right: const pw.BorderSide(
                color: pdf.PdfColors.grey600,
                width: 0.8,
              ),
            ),
            data: itemsRows,
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(3),
              5: const pw.FlexColumnWidth(3),
              6: const pw.FlexColumnWidth(3),
              7: const pw.FlexColumnWidth(3),
              8: const pw.FlexColumnWidth(3),
            },
          ),
          pw.SizedBox(height: 8),

          // Total Row: In-words on left, Total(INR) box on right
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: _items.isNotEmpty
                    ? pw.Text(
                        'Total (in words): ${_inWords(_grandTotal.round())} ONLY',
                        style: pw.TextStyle(
                          font: fontForWeight(600),
                          color: pdf.PdfColors.black,
                          fontSize: 11,
                        ),
                      )
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: pdf.PdfColors.black,
                          width: 2,
                        ),
                      ),
                    ),
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Text(
                      'Total (INR)',
                      style: pw.TextStyle(font: fontForWeight(600)),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: pdf.PdfColors.black,
                          width: 2,
                        ),
                      ),
                    ),
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Text(
                      formatCurrency.format(_grandTotal),
                      style: pw.TextStyle(font: fontForWeight(600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // Bank Details and UPI
          pw.Container(
            width: pdf.PdfPageFormat.a4.width - 56,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Bank Details',
                        style: pw.TextStyle(
                          font: fontForWeight(900),
                          color: pdf.PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      if (_accountName.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Account Name: ',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 16),
                            pw.Text(
                              _accountName.text.trim(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_accountNumber.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Account Number: ',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 5),
                            pw.Text(
                              _accountNumber.text.trim(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_ifsc.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'IFSC: ',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 71),
                            pw.Text(
                              _ifsc.text.trim(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_accountType.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Account Type: ',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 22),
                            pw.Text(
                              _accountType.text.trim(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                      if (_bank.text.trim().isNotEmpty)
                        pw.Row(
                          children: [
                            pw.Text(
                              'Bank: ',
                              style: pw.TextStyle(font: fontForWeight(600)),
                            ),
                            pw.SizedBox(width: 69),
                            pw.Text(
                              _bank.text.trim(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: fontForWeight(300)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'UPI - Scan to Pay',
                        style: pw.TextStyle(
                          font: fontForWeight(700),
                          color: pdf.PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        '(Maximum of 1 Lakh can be transferred via UPI)',
                        style: pw.TextStyle(fontSize: 10),
                      ),
                      pw.SizedBox(height: 8),
                      if (_upiId.text.trim().isNotEmpty) ...[
                        _buildQrCodePdf(upiQrImage),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'UPI ID: ${_upiId.text.trim()}',
                          style: pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Terms and Conditions
          pw.Container(
            // padding removed intentionally
            child: pw.Text(
              'Terms and Conditions',
              style: pw.TextStyle(
                color: pdf.PdfColors.deepPurple,
                font: fontForWeight(900),
                fontSize: 12,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          if (_terms.text.trim().isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: _terms.text
                  .split('\n')
                  .where((e) => e.trim().isNotEmpty)
                  .map(
                    (e) => pw.Text(
                      e.trim(),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  )
                  .toList(),
            ),

          // Footer handled by MultiPage.footer
        ],
      ),
    );

    return doc.save();
  }

  Future<pw.MemoryImage?> _loadLogoImage() async {
    try {
      final imageData = await DefaultAssetBundle.of(
        context,
      ).load('assets/Webutsav__3.png');
      return pw.MemoryImage(imageData.buffer.asUint8List());
    } catch (e) {
      return null;
    }
  }

  pw.Widget _buildQrCodePdf(pw.ImageProvider? imageProvider) {
    if (imageProvider != null) {
      return pw.Image(imageProvider, width: 100, height: 100);
    }
    return pw.Container(width: 100, height: 100, color: pdf.PdfColors.grey200);
  }

  Future<pw.ImageProvider> _generateQrImage(String data) async {
    final qrImage = await QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    ).toImageData(200);
    return pw.MemoryImage(qrImage!.buffer.asUint8List());
  }

  Future<void> _downloadPdf() async {
    try {
      if (_items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add at least one item to generate the PDF'),
          ),
        );
        return;
      }
      if (_billedByName.text.trim().isEmpty ||
          _billedToName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in Billed By and Billed To names'),
          ),
        );
        return;
      }

      final bytes = await _generatePdfBytes();
      final namePart = _invoiceNo.text.trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _invoiceNo.text.trim();

      await FileSaver.instance.saveFile(
        name: 'Webutsav_Invoice-$namePart',
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice PDF saved successfully')),
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save PDF: $e')));
      debugPrint('PDF Generation Error: $e\n$stackTrace');
    }
  }

  String _inWords(int number) {
    final units = [
      '',
      'ONE',
      'TWO',
      'THREE',
      'FOUR',
      'FIVE',
      'SIX',
      'SEVEN',
      'EIGHT',
      'NINE',
      'TEN',
      'ELEVEN',
      'TWELVE',
      'THIRTEEN',
      'FOURTEEN',
      'FIFTEEN',
      'SIXTEEN',
      'SEVENTEEN',
      'EIGHTEEN',
      'NINETEEN',
    ];
    final tens = [
      '',
      '',
      'TWENTY',
      'THIRTY',
      'FORTY',
      'FIFTY',
      'SIXTY',
      'SEVENTY',
      'EIGHTY',
      'NINETY',
    ];

    String two(int n) {
      if (n < 20) return units[n];
      final t = n ~/ 10, u = n % 10;
      return u == 0 ? tens[t] : '${tens[t]} ${units[u]}';
    }

    String three(int n) {
      final h = n ~/ 100, rest = n % 100;
      if (h == 0) return two(rest);
      return rest == 0
          ? '${units[h]} HUNDRED'
          : '${units[h]} HUNDRED ${two(rest)}';
    }

    if (number == 0) return '';

    final sb = StringBuffer();
    int n = number;

    int crore = n ~/ 10000000;
    n %= 10000000;
    int lakh = n ~/ 100000;
    n %= 100000;
    int thousand = n ~/ 1000;
    n %= 1000;
    int hundred = n;

    if (crore > 0) sb.write('${two(crore)} CRORE ');
    if (lakh > 0) sb.write('${two(lakh)} LAKH ');
    if (thousand > 0) sb.write('${two(thousand)} THOUSAND ');
    if (hundred > 0) sb.write('${three(hundred)} ');

    return sb.toString().trim();
  }

  String _upiUri() {
    final pa = _upiId.text.trim();
    final pn = Uri.encodeComponent(_accountName.text.trim());
    final am = _grandTotal.toStringAsFixed(2);
    return 'upi://pay?pa=$pa&pn=$pn&am=$am&cu=INR&tn=${Uri.encodeComponent('Invoice ${_invoiceNo.text.trim()}')}';
  }

  Future<void> _showAddItemDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final rateCtrl = TextEditingController();

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Item'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter item name'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: qtyCtrl,
                          decoration: const InputDecoration(labelText: 'Qty'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final d = double.tryParse(v?.trim() ?? '');
                            if (d == null || d <= 0) return 'Invalid qty';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: rateCtrl,
                          decoration: const InputDecoration(labelText: 'Rate'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final d = double.tryParse(v?.trim() ?? '');
                            if (d == null || d < 0) return 'Invalid rate';
                            return null;
                          },
                        ),
                      ),
                    ],
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
                if (formKey.currentState?.validate() != true) return;
                setState(() {
                  _items.add(
                    _InvoiceItem(
                      name: nameCtrl.text.trim(),
                      qty: double.parse(qtyCtrl.text.trim()),
                      rate: double.parse(rateCtrl.text.trim()),
                    ),
                  );
                });
                Navigator.of(context).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditItemDialog(int index, _InvoiceItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final qtyCtrl = TextEditingController(text: item.qty.toString());
    final rateCtrl = TextEditingController(text: item.rate.toString());

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Item'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter item name'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: qtyCtrl,
                          decoration: const InputDecoration(labelText: 'Qty'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final d = double.tryParse(v?.trim() ?? '');
                            if (d == null || d <= 0) return 'Invalid qty';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: rateCtrl,
                          decoration: const InputDecoration(labelText: 'Rate'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final d = double.tryParse(v?.trim() ?? '');
                            if (d == null || d < 0) return 'Invalid rate';
                            return null;
                          },
                        ),
                      ),
                    ],
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
                if (formKey.currentState?.validate() != true) return;
                setState(() {
                  _items[index] = _InvoiceItem(
                    name: nameCtrl.text.trim(),
                    qty: double.parse(qtyCtrl.text.trim()),
                    rate: double.parse(rateCtrl.text.trim()),
                  );
                });
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _billedByName.dispose();
    _billedByAddress.dispose();
    _billedByEmail.dispose();
    _gstin.dispose();
    _pan.dispose();
    _billedToName.dispose();
    _billedToAddress.dispose();
    _billedToGstin.dispose();
    _billedToMobile.dispose();
    _billedToEmail.dispose();
    _accountName.dispose();
    _accountNumber.dispose();
    _ifsc.dispose();
    _accountType.dispose();
    _bank.dispose();
    _upiId.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Invoice Builder',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF334155)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: _downloadPdf,
            icon: const Icon(Icons.download, color: Colors.white),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final rb = ResponsiveBreakpoints.of(context);
          final isWide = rb.largerThan(TABLET);
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(flex: 5, child: _buildForm()),
              const SizedBox(width: 16),
              Flexible(flex: 7, child: _buildPreview()),
            ],
          );

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: isWide
                ? content
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildForm(),
                        const SizedBox(height: 16),
                        _buildPreview(),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: false,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Invoice Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final rb = ResponsiveBreakpoints.of(context);
                    final layout = rb.smallerOrEqualTo(MOBILE)
                        ? ResponsiveRowColumnType.COLUMN
                        : ResponsiveRowColumnType.ROW;
                    return ResponsiveRowColumn(
                      layout: layout,
                      rowSpacing: 12,
                      columnSpacing: 12,
                      children: [
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _invoiceNo,
                            decoration: deco('Invoice No'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: _DateField(
                            label: 'Invoice Date',
                            value: _invoiceDate,
                            onChanged: (d) => setState(() => _invoiceDate = d),
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: _DateField(
                            label: 'Due Date',
                            value: _dueDate,
                            onChanged: (d) => setState(() => _dueDate = d),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Billed By',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _billedByName,
                  decoration: deco('Name'),
                  onChanged: (_) {
                    _saveField(_kBilledByName, _billedByName.text);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _billedByAddress,
                  decoration: deco('Address'),
                  maxLines: 2,
                  onChanged: (_) {
                    _saveField(_kBilledByAddress, _billedByAddress.text);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final rb = ResponsiveBreakpoints.of(context);
                    final layout = rb.smallerOrEqualTo(MOBILE)
                        ? ResponsiveRowColumnType.COLUMN
                        : ResponsiveRowColumnType.ROW;
                    return ResponsiveRowColumn(
                      layout: layout,
                      rowSpacing: 12,
                      columnSpacing: 12,
                      children: [
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _gstin,
                            decoration: deco('GSTIN'),
                            onChanged: (_) {
                              _saveField(_kBilledByGstin, _gstin.text);
                              setState(() {});
                            },
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _pan,
                            decoration: deco('PAN'),
                            onChanged: (_) {
                              _saveField(_kBilledByPan, _pan.text);
                              setState(() {});
                            },
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _billedByEmail,
                            decoration: deco('Email'),
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) {
                              _saveField(_kBilledByEmail, _billedByEmail.text);
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Billed To',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _billedToName,
                  decoration: deco('Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _billedToAddress,
                  decoration: deco('Address'),
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final rb = ResponsiveBreakpoints.of(context);
                    final layout = rb.smallerOrEqualTo(MOBILE)
                        ? ResponsiveRowColumnType.COLUMN
                        : ResponsiveRowColumnType.ROW;
                    return ResponsiveRowColumn(
                      layout: layout,
                      rowSpacing: 12,
                      columnSpacing: 12,
                      children: [
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _billedToGstin,
                            decoration: deco('GSTIN'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _billedToMobile,
                            decoration: deco('Mobile No'),
                            keyboardType: TextInputType.phone,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        ResponsiveRowColumnItem(
                          rowFlex: 1,
                          child: TextFormField(
                            controller: _billedToEmail,
                            decoration: deco('Email'),
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Item',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showAddItemDialog,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white24,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              Expanded(flex: 5, child: Text(_items[i].name)),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _items[i].qty % 1 == 0
                                      ? _items[i].qty.toStringAsFixed(0)
                                      : _items[i].qty.toString(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _inCurrency.format(_items[i].rate),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _inCurrency.format(_items[i].amount),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 84,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Tooltip(
                                      message: 'Edit',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () =>
                                            _showEditItemDialog(i, _items[i]),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Delete',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _items.removeAt(i);
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No items added. Click Add Item to insert.',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Bank / UPI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    TextFormField(
                      controller: _accountName,
                      decoration: deco('Account Name'),
                      onChanged: (_) {
                        _saveField(_kAccountName, _accountName.text);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _accountNumber,
                            decoration: deco('Account Number'),
                            onChanged: (_) {
                              _saveField(_kAccountNumber, _accountNumber.text);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _ifsc,
                            decoration: deco('IFSC'),
                            onChanged: (_) {
                              _saveField(_kIfsc, _ifsc.text);
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _accountType,
                            decoration: deco('Account Type'),
                            onChanged: (_) {
                              _saveField(_kAccountType, _accountType.text);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _bank,
                            decoration: deco('Bank'),
                            onChanged: (_) {
                              _saveField(_kBank, _bank.text);
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _upiId,
                      decoration: deco('UPI ID'),
                      onChanged: (_) {
                        _saveField(_kUpiId, _upiId.text);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Terms and Conditions',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _terms,
                      decoration: deco(
                        'Terms and Conditions (one per line)',
                      ).copyWith(hintText: 'e.g. Please pay within 15 days...'),
                      maxLines: 4,
                      onChanged: (_) {
                        _saveField(_kTerms, _terms.text);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Invoice',
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _kv('Invoice No #', _invoiceNo.text),
                        _kv(
                          'Invoice Date',
                          DateFormat('MMM d, y').format(_invoiceDate),
                        ),
                        _kv(
                          'Due Date',
                          DateFormat('MMM d, y').format(_dueDate),
                        ),
                      ],
                    ),
                  ),
                  // Company logo
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 120,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/Webutsav__3.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Center(
                                child: Text(
                                  'Logo not found',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Billed sections (responsive)
              Builder(
                builder: (context) {
                  final rb = ResponsiveBreakpoints.of(context);
                  final narrow = !rb.largerThan(TABLET);
                  final billedBy = _panel(
                    title: 'Billed By',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _billedByName.text,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(_billedByAddress.text),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'GSTIN: ${_gstin.text}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            // Text(_gstin.text,),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              'PAN: ${_pan.text}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            // Text(_pan.text),
                          ],
                        ),
                        if (_billedByEmail.text.trim().isNotEmpty)
                          Row(
                            children: [
                              const Text(
                                'Email: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(_billedByEmail.text),
                            ],
                          ),
                      ],
                    ),
                  );
                  final billedTo = _panel(
                    title: 'Billed To',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _billedToName.text,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(_billedToAddress.text),
                        if (_billedToGstin.text.trim().isNotEmpty)
                          Row(
                            children: [
                              const Text(
                                'GSTIN: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(_billedToGstin.text),
                            ],
                          ),
                        if (_billedToMobile.text.trim().isNotEmpty)
                          Row(
                            children: [
                              const Text(
                                'Mobile: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(_billedToMobile.text),
                            ],
                          ),
                        if (_billedToEmail.text.trim().isNotEmpty)
                          Row(
                            children: [
                              const Text(
                                'Email: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(_billedToEmail.text),
                            ],
                          ),
                      ],
                    ),
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        billedBy,
                        const SizedBox(height: 16),
                        billedTo,
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: billedBy),
                        const SizedBox(width: 16),
                        Expanded(child: billedTo),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              // Items header
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 36,
                      child: Text(
                        '',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        'Item',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'GST Rate',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Quantity',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Rate',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Amount',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'CGST',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'SGST',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${i + 1}.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                            Expanded(flex: 6, child: Text(_items[i].name)),
                            Container(
                              width: 1,
                              height: 20,
                              color: const Color(0xFFE5E7EB),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('18%', textAlign: TextAlign.center),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _items[i].qty % 1 == 0
                                    ? _items[i].qty.toStringAsFixed(0)
                                    : _items[i].qty.toString(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _inCurrency.format(_items[i].rate),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _inCurrency.format(_items[i].amount),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _inCurrency.format(_items[i].amount * 0.09),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _inCurrency.format(_items[i].amount * 0.09),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _inCurrency.format(_items[i].amount * 1.18),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              if (_items.isNotEmpty)
                Text(
                  'Total (in words): ${_inWords(_grandTotal.round())} ONLY',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),

              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 150,
                  child: Column(
                    children: [
                      if (_items.isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.black87,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Total (INR)',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 1),
                            Expanded(
                              child: Container(
                                alignment: Alignment.centerRight,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.black87,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _inCurrency.format(_grandTotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Builder(
                builder: (context) {
                  final rb = ResponsiveBreakpoints.of(context);
                  final narrow = !rb.largerThan(TABLET);
                  final bankPanel = _panel(
                    title: 'Bank Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Account Name: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _accountName.text,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'Account Number: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _accountNumber.text,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'IFSC: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(_ifsc.text, textAlign: TextAlign.center),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'Account Type: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _accountType.text,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'Bank: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(_bank.text, textAlign: TextAlign.center),
                          ],
                        ),
                      ],
                    ),
                  );
                  final qrPanel = _panel(
                    title: 'UPI - Scan to Pay',
                    titleColor: Colors.deepPurple,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '(Maximum of 1 Lakh can be transferred via UPI)',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, c2) {
                            final size = c2.maxWidth * 0.6;
                            return Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.black12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: QrImageView(
                                  data: _upiUri(),
                                  version: QrVersions.auto,
                                  size: size,
                                  gapless: true,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(_upiId.text, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        bankPanel,
                        const SizedBox(height: 16),
                        qrPanel,
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: bankPanel),
                        const SizedBox(width: 16),
                        Expanded(child: qrPanel),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Terms and Conditions',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final line in _terms.text.split('\n'))
                if (line.trim().isNotEmpty) _BulletText(line.trim()),

              const SizedBox(height: 32),
              Center(
                child: Text(
                  'This is an electronically generated document, no signature is required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 4,
          child: Text(k, style: const TextStyle(color: Colors.black54)),
        ),
        const SizedBox(width: 2),
        Expanded(flex: 6, child: Text(v, textAlign: TextAlign.left)),
      ],
    ),
  );

  Widget _panel({
    required String title,
    Color? titleColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: titleColor ?? Colors.deepPurple.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// Represents a single invoice line item
class _InvoiceItem {
  final String name;
  final double qty;
  final double rate;
  const _InvoiceItem({
    required this.name,
    required this.qty,
    required this.rate,
  });
  double get amount => qty * rate;
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(
      text: DateFormat('MMM d, y').format(value),
    );
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDate: value,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _BulletText extends StatelessWidget {
  final String text;
  const _BulletText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}
