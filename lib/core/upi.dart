/// UPI payment links and GSTIN / UPI ID validation.
class Upi {
  Upi._();

  static final _upiId = RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$');
  static final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  /// `upi://pay?pa=<id>&pn=<name>&am=<total>&cu=INR&tn=Bill <number>`
  /// The UPI ID is left unencoded (some UPI apps do not decode %40); the other fields are URL-encoded.
  static String uri({required String upiId, required String payeeName, required double amount, required String note}) {
    return 'upi://pay?pa=${upiId.trim()}'
        '&pn=${Uri.encodeComponent(payeeName)}'
        '&am=${amount.toStringAsFixed(2)}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent(note)}';
  }

  static bool isValidUpiId(String? id) => id != null && _upiId.hasMatch(id.trim());

  static bool isValidGstin(String? gstin) => gstin != null && _gstin.hasMatch(gstin.trim());
}
