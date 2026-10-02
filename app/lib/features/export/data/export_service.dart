import 'dart:io';

import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Everything a month contains, in one object, so the three exporters cannot
/// disagree about what a month is.
class MonthExport {
  const MonthExport({required this.summary, required this.expenses});

  final BudgetSummary summary;
  final List<Expense> expenses;
}

/// Exports a month as XLSX, CSV or PDF.
///
/// The PRD's "Excel replacement": each file preserves transaction history,
/// monthly statistics and savings information, so an exported month is a
/// complete record rather than a screenshot of one screen.
///
/// Amounts are written as rupees with two decimals — not as paise. The internal
/// representation is an implementation detail, and a spreadsheet full of
/// integers a hundred times too large is not a record anyone can use.
class ExportService {
  const ExportService();

  static final _date = DateFormat('yyyy-MM-dd');

  double _rupees(int minor) => minor / 100;

  Future<File> writeXlsx(MonthExport data) async {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();

    _buildSummarySheet(book['Summary'], data);
    _buildExpensesSheet(book['Transactions'], data);

    // createExcel() seeds a 'Sheet1'; leaving it produces a workbook whose first
    // tab is empty, which reads as a broken export.
    if (defaultSheet != null && defaultSheet != 'Summary') {
      book.delete(defaultSheet);
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw const FileSystemException('Could not encode the workbook');
    }
    return _write('budgetwise_${data.summary.period.isoDate}.xlsx', bytes);
  }

  void _buildSummarySheet(Sheet sheet, MonthExport data) {
    final s = data.summary;
    final rows = <List<Object?>>[
      ['BudgetWise — ${s.period.label}'],
      [],
      ['Income', _rupees(s.income.minor)],
      ['Savings target', _rupees(s.savingsTarget.minor)],
      ['Savings actual', _rupees(s.savedActual.minor)],
      ['Savings confirmed', if (s.isSavingsConfirmed) 'Yes' else 'No'],
      if (s.investmentTarget != null)
        ['Investment target', _rupees(s.investmentTarget!.minor)],
      ['Invested', _rupees(s.investedActual.minor)],
      [],
      ['Spendable', _rupees(s.spendable.minor)],
      ['Spent', _rupees(s.spent.minor)],
      ['Remaining', _rupees(s.remaining.minor)],
      [],
      ['Transactions', s.expenseCount],
      ['Days with activity', s.daysWithExpenses],
      ['Days in month', s.period.totalDays],
    ];

    for (final row in rows) {
      sheet.appendRow([for (final cell in row) _cell(cell)]);
    }
  }

  void _buildExpensesSheet(Sheet sheet, MonthExport data) {
    sheet.appendRow([
      for (final header in ['Date', 'Amount', 'Method', 'Note'])
        TextCellValue(header),
    ]);

    for (final expense in data.expenses) {
      sheet.appendRow([
        TextCellValue(_date.format(expense.spentOn)),
        DoubleCellValue(_rupees(expense.amount.minor)),
        TextCellValue(expense.paymentMethod.label),
        TextCellValue(expense.note ?? ''),
      ]);
    }
  }

  CellValue _cell(Object? value) => switch (value) {
    null => TextCellValue(''),
    final int v => IntCellValue(v),
    final double v => DoubleCellValue(v),
    _ => TextCellValue(value.toString()),
  };

  Future<File> writeCsv(MonthExport data) async {
    final s = data.summary;

    // One file, two labelled blocks. A CSV cannot have sheets, and splitting
    // into separate files would mean the user has to keep them together
    // themselves.
    final rows = <List<Object?>>[
      ['BudgetWise', s.period.label],
      [],
      ['SUMMARY'],
      ['Income', _rupees(s.income.minor)],
      ['Savings target', _rupees(s.savingsTarget.minor)],
      ['Savings actual', _rupees(s.savedActual.minor)],
      ['Spendable', _rupees(s.spendable.minor)],
      ['Spent', _rupees(s.spent.minor)],
      ['Remaining', _rupees(s.remaining.minor)],
      [],
      ['TRANSACTIONS'],
      ['Date', 'Amount', 'Method', 'Note'],
      for (final e in data.expenses)
        [
          _date.format(e.spentOn),
          _rupees(e.amount.minor),
          e.paymentMethod.label,
          e.note ?? '',
        ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    return _write('budgetwise_${s.period.isoDate}.csv', csv.codeUnits);
  }

  Future<File> writePdf(MonthExport data) async {
    final s = data.summary;
    final document = pw.Document()
      ..addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Header(level: 0, text: 'BudgetWise — ${s.period.label}'),
            pw.SizedBox(height: 8),
            _pdfSummary(s),
            pw.SizedBox(height: 20),
            pw.Text(
              'Transactions',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _pdfExpenses(data),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
        ),
      );

    return _write('budgetwise_${s.period.isoDate}.pdf', await document.save());
  }

  pw.Widget _pdfSummary(BudgetSummary s) {
    String money(int minor) => 'Rs ${_rupees(minor).toStringAsFixed(2)}';

    return pw.TableHelper.fromTextArray(
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headers: ['', ''],
      data: [
        ['Income', money(s.income.minor)],
        ['Savings target', money(s.savingsTarget.minor)],
        ['Savings actual', money(s.savedActual.minor)],
        ['Spendable', money(s.spendable.minor)],
        ['Spent', money(s.spent.minor)],
        ['Remaining', money(s.remaining.minor)],
        ['Transactions', '${s.expenseCount}'],
      ],
    );
  }

  pw.Widget _pdfExpenses(MonthExport data) {
    if (data.expenses.isEmpty) {
      return pw.Text(
        'No transactions recorded.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }

    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headers: ['Date', 'Amount', 'Method', 'Note'],
      data: [
        for (final e in data.expenses)
          [
            _date.format(e.spentOn),
            'Rs ${_rupees(e.amount.minor).toStringAsFixed(2)}',
            e.paymentMethod.label,
            e.note ?? '',
          ],
      ],
    );
  }

  Future<File> _write(String filename, List<int> bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> share(File file, String label) => SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: label),
  );
}
