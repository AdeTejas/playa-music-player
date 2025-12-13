import 'package:on_audio_query/on_audio_query.dart';

class AndroidAudioQuery {
  static final AndroidAudioQuery _instance = AndroidAudioQuery._();
  static AndroidAudioQuery get instance => _instance;
  AndroidAudioQuery._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<SongModel>> querySongsFromDirectory(String directoryPath) async {
    try {
      final songs = await _audioQuery.querySongs(
        path: directoryPath,
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      return songs;
    } catch (e) {
      return [];
    }
  }
}
