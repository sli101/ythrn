// ignore_for_file: deprecated_member_use
//
// واجهة `package:drift/web.dart` مهجورة (وضع إصلاح الأخطاء فقط) لكنها ما زالت
// تعمل، وملفا `sql-wasm.js` و`sql-wasm.wasm` موجودان في مجلد `web/`.
// الانتقال إلى `package:drift/wasm.dart` يتطلب وضع `sqlite3.wasm` و
// `drift_worker.js` في مجلد `web/` (انظر https://drift.simonbinder.eu/web).
import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase openLazyConnection() {
  return LazyDatabase(() async {
    return WebDatabase('ythrn');
  });
}
