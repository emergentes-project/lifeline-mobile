import '../../consultation/domain/models/saved_consultation.dart';

class DeliveryConfirmationNotices {
  DeliveryConfirmationNotices(this.show);
  final Future<void> Function(int id, String message) show;
  final _shown = <int>{};

  Future<void> announce(
    List<SavedConsultation> before,
    List<SavedConsultation> after,
  ) async {
    final previous = {for (final row in before) row.id: row.syncStatus};
    for (final row in after) {
      if (!previous.containsKey(row.id)) continue;
      if (!row.draft.helpRequested) continue;
      if (previous[row.id] == 'confirmed' || row.syncStatus != 'confirmed') {
        continue;
      }
      if (!_shown.add(row.id)) continue;
      await show(row.id, 'Envío confirmado');
    }
  }
}
