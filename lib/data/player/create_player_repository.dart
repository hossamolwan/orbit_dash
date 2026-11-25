import 'package:cloud_firestore/cloud_firestore.dart';

import '../../player_identity.dart';
import 'authenticated_player_repository.dart';
import 'firestore_player_data_source.dart';
import 'player_repository.dart';

/// Creates the authenticated player repository after identity initialization.
///
/// The identity service is normally obtained from
/// `createFirebasePlayerIdentityService`, which initializes Firebase before
/// returning it. This function awaits the service initialization before
/// constructing the Firestore adapter. The adapter and repository constructors
/// perform no reads or writes; player documents are accessed only by explicit
/// repository operations.
Future<PlayerRepository> createPlayerRepository({
  required PlayerIdentityService identityService,
  FirebaseFirestore? firestore,
}) async {
  await identityService.initialize();
  final dataSource = FirestorePlayerDataSource(firestore: firestore);
  return AuthenticatedPlayerRepository(identityService, dataSource);
}
