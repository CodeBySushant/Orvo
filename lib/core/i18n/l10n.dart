import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_provider.dart' show sharedPreferencesProvider;

/// FEATURE (#24): in-app localization with instant switching.
///
/// Strings live in positional lists indexed by [AppLanguage] — watching
/// [l10nProvider] means every localized widget rebuilds the moment the
/// language changes, so switching is seamless (no restart, no flicker).
/// Material's own widgets (tooltips, date pickers, text selection menus)
/// are localized via flutter_localizations in app.dart.

enum AppLanguage {
  en('English', Locale('en')),
  hi('हिन्दी', Locale('hi')),
  es('Español', Locale('es')),
  ja('日本語', Locale('ja')),
  ko('한국어', Locale('ko')),
  de('Deutsch', Locale('de')),
  fr('Français', Locale('fr')),
  ru('Русский', Locale('ru'));

  const AppLanguage(this.nativeName, this.locale);
  final String nativeName;
  final Locale locale;
}

const _kLanguageKey = 'orvo.language';

class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_kLanguageKey);
    return AppLanguage.values.firstWhere(
      (l) => l.name == stored,
      orElse: () => AppLanguage.en,
    );
  }

  void set(AppLanguage language) {
    state = language;
    ref
        .read(sharedPreferencesProvider)
        .setString(_kLanguageKey, language.name);
  }
}

final languageProvider =
    NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);

final l10nProvider = Provider<L10n>((ref) => L10n(ref.watch(languageProvider)));

/// All UI strings. Order everywhere: en, hi, es, ja, ko, de, fr, ru.
class L10n {
  const L10n(this.lang);
  final AppLanguage lang;

  String _s(List<String> v) => v[lang.index];

  // --- Navigation ---------------------------------------------------------
  String get home => _s(['Home', 'होम', 'Inicio', 'ホーム', '홈', 'Start', 'Accueil', 'Главная']);
  String get search => _s(['Search', 'खोजें', 'Buscar', '検索', '검색', 'Suchen', 'Recherche', 'Поиск']);
  String get library => _s(['Library', 'लाइब्रेरी', 'Biblioteca', 'ライブラリ', '라이브러리', 'Bibliothek', 'Bibliothèque', 'Библиотека']);
  String get settings => _s(['Settings', 'सेटिंग्स', 'Ajustes', '設定', '설정', 'Einstellungen', 'Réglages', 'Настройки']);

  // --- Home ---------------------------------------------------------------
  String get goodMorning => _s(['Good Morning', 'सुप्रभात', 'Buenos días', 'おはようございます', '좋은 아침', 'Guten Morgen', 'Bonjour', 'Доброе утро']);
  String get goodAfternoon => _s(['Good Afternoon', 'नमस्ते', 'Buenas tardes', 'こんにちは', '좋은 오후', 'Guten Tag', 'Bon après-midi', 'Добрый день']);
  String get goodEvening => _s(['Good Evening', 'शुभ संध्या', 'Buenas noches', 'こんばんは', '좋은 저녁', 'Guten Abend', 'Bonsoir', 'Добрый вечер']);
  String get musicLover => _s(['Music Lover', 'संगीत प्रेमी', 'Melómano', '音楽好き', '음악 애호가', 'Musikfan', 'Mélomane', 'Меломан']);
  String get yourName => _s(['Your name', 'आपका नाम', 'Tu nombre', 'お名前', '이름', 'Dein Name', 'Votre nom', 'Ваше имя']);
  String get greetHint => _s(['How should Orvo greet you?', 'Orvo आपको कैसे संबोधित करे?', '¿Cómo debería saludarte Orvo?', 'Orvoは何とお呼びすれば？', 'Orvo가 뭐라고 불러드릴까요?', 'Wie soll Orvo dich begrüßen?', 'Comment Orvo doit-il vous saluer ?', 'Как Orvo вас приветствовать?']);
  String get cancel => _s(['Cancel', 'रद्द करें', 'Cancelar', 'キャンセル', '취소', 'Abbrechen', 'Annuler', 'Отмена']);
  String get save => _s(['Save', 'सहेजें', 'Guardar', '保存', '저장', 'Speichern', 'Enregistrer', 'Сохранить']);
  String get recentlyPlayed => _s(['Recently Played', 'हाल में चलाए गए', 'Reproducido recientemente', '最近再生した項目', '최근 재생', 'Zuletzt gespielt', 'Écoutés récemment', 'Недавно прослушанные']);
  String get favoritePlaylists => _s(['Favorite Playlists', 'पसंदीदा प्लेलिस्ट', 'Playlists favoritas', 'お気に入りプレイリスト', '즐겨찾는 재생목록', 'Lieblings-Playlists', 'Playlists favorites', 'Любимые плейлисты']);
  String get recentlyAdded => _s(['Recently Added', 'हाल में जोड़े गए', 'Añadido recientemente', '最近追加した項目', '최근 추가', 'Zuletzt hinzugefügt', 'Ajoutés récemment', 'Недавно добавленные']);
  String get browseByGenre => _s(['Browse by Genre', 'शैली के अनुसार देखें', 'Explorar por género', 'ジャンルで探す', '장르별 탐색', 'Nach Genre stöbern', 'Parcourir par genre', 'По жанрам']);
  String get seeAll => _s(['See All', 'सभी देखें', 'Ver todo', 'すべて見る', '모두 보기', 'Alle anzeigen', 'Tout voir', 'Все']);
  String get likedSongs => _s(['Liked Songs', 'पसंद किए गए गाने', 'Canciones que te gustan', 'お気に入りの曲', '좋아요 표시한 곡', 'Lieblingssongs', 'Titres aimés', 'Понравившиеся']);
  String nSongs(int n) => '$n ${_s(['Songs', 'गाने', 'canciones', '曲', '곡', 'Songs', 'titres', 'песен'])}';
  String get createFirstPlaylist => _s(['Create your first playlist', 'अपनी पहली प्लेलिस्ट बनाएँ', 'Crea tu primera playlist', '最初のプレイリストを作成', '첫 재생목록 만들기', 'Erstelle deine erste Playlist', 'Créez votre première playlist', 'Создайте первый плейлист']);
  String get noMusicYet => _s(['No music yet', 'अभी कोई संगीत नहीं', 'Aún no hay música', 'まだ音楽がありません', '아직 음악이 없음', 'Noch keine Musik', 'Pas encore de musique', 'Музыки пока нет']);
  String get addAudioFiles => _s(['Add audio files to this device and Orvo will pick them up.', 'इस डिवाइस में ऑडियो फ़ाइलें जोड़ें, Orvo उन्हें ढूँढ लेगा।', 'Añade archivos de audio y Orvo los encontrará.', '端末に音楽ファイルを追加するとOrvoが読み込みます。', '기기에 오디오 파일을 추가하면 Orvo가 찾습니다.', 'Füge Audiodateien hinzu — Orvo findet sie.', 'Ajoutez des fichiers audio, Orvo les trouvera.', 'Добавьте аудиофайлы — Orvo их найдёт.']);

  // --- Search -------------------------------------------------------------
  String get searchHint => _s(['Songs, artists, albums…', 'गाने, कलाकार, एल्बम…', 'Canciones, artistas, álbumes…', '曲、アーティスト、アルバム…', '곡, 아티스트, 앨범…', 'Songs, Künstler, Alben…', 'Titres, artistes, albums…', 'Песни, исполнители, альбомы…']);
  String get recent => _s(['RECENT', 'हाल के', 'RECIENTES', '最近', '최근', 'ZULETZT', 'RÉCENT', 'НЕДАВНИЕ']);
  String get clear => _s(['Clear', 'साफ़ करें', 'Borrar', '消去', '지우기', 'Löschen', 'Effacer', 'Очистить']);
  String get browse => _s(['BROWSE', 'ब्राउज़ करें', 'EXPLORAR', '見つける', '둘러보기', 'ENTDECKEN', 'PARCOURIR', 'ОБЗОР']);
  String get topResult => _s(['TOP RESULT', 'शीर्ष परिणाम', 'MEJOR RESULTADO', 'トップの結果', '상위 결과', 'TOP-TREFFER', 'MEILLEUR RÉSULTAT', 'ЛУЧШИЙ РЕЗУЛЬТАТ']);
  String get songsCaps => _s(['SONGS', 'गाने', 'CANCIONES', '曲', '곡', 'SONGS', 'TITRES', 'ПЕСНИ']);
  String get albumsCaps => _s(['ALBUMS', 'एल्बम', 'ÁLBUMES', 'アルバム', '앨범', 'ALBEN', 'ALBUMS', 'АЛЬБОМЫ']);
  String get artistsCaps => _s(['ARTISTS', 'कलाकार', 'ARTISTAS', 'アーティスト', '아티스트', 'KÜNSTLER', 'ARTISTES', 'ИСПОЛНИТЕЛИ']);
  String get playlistsCaps => _s(['PLAYLISTS', 'प्लेलिस्ट', 'PLAYLISTS', 'プレイリスト', '재생목록', 'PLAYLISTS', 'PLAYLISTS', 'ПЛЕЙЛИСТЫ']);
  String get foldersCaps => _s(['FOLDERS', 'फ़ोल्डर', 'CARPETAS', 'フォルダ', '폴더', 'ORDNER', 'DOSSIERS', 'ПАПКИ']);
  String get songBadge => _s(['SONG', 'गाना', 'CANCIÓN', '曲', '곡', 'SONG', 'TITRE', 'ПЕСНЯ']);
  String get genres => _s(['Genres', 'शैलियाँ', 'Géneros', 'ジャンル', '장르', 'Genres', 'Genres', 'Жанры']);
  String get shuffleAll => _s(['Shuffle all', 'सभी शफ़ल करें', 'Aleatorio', 'すべてシャッフル', '전체 셔플', 'Alles mischen', 'Lecture aléatoire', 'Перемешать всё']);
  String noResultsFor(String q) => _s(['No results for "$q"', '"$q" के लिए कोई परिणाम नहीं', 'Sin resultados para "$q"', '「$q」の検索結果はありません', '"$q" 검색 결과 없음', 'Keine Ergebnisse für "$q"', 'Aucun résultat pour "$q"', 'Ничего не найдено: "$q"']);
  String get checkSpelling => _s(['Check the spelling or try the artist\nor album name instead.', 'वर्तनी जाँचें या कलाकार/एल्बम\nके नाम से खोजें।', 'Revisa la ortografía o busca por\nartista o álbum.', 'つづりを確認するか、アーティスト名\nやアルバム名で試してください。', '철자를 확인하거나 아티스트/앨범\n이름으로 검색해 보세요.', 'Prüfe die Schreibweise oder suche\nnach Künstler oder Album.', 'Vérifiez l\'orthographe ou essayez\nl\'artiste ou l\'album.', 'Проверьте написание или ищите\nпо исполнителю или альбому.']);

  // --- Player -------------------------------------------------------------
  String get upNextCaps => _s(['UP NEXT', 'आगे', 'A CONTINUACIÓN', '次に再生', '다음 곡', 'ALS NÄCHSTES', 'À SUIVRE', 'ДАЛЕЕ']);
  String get upNext => _s(['Up next', 'आगे चलने वाले', 'A continuación', '次に再生', '다음 트랙', 'Als Nächstes', 'À suivre', 'Далее']);
  String nTracks(int n) => '$n ${_s(['tracks', 'ट्रैक', 'pistas', '曲', '곡', 'Titel', 'pistes', 'треков'])}';
  String get queueEmpty => _s(['Queue is empty', 'क्यू खाली है', 'La cola está vacía', 'キューは空です', '대기열이 비어 있음', 'Warteschlange ist leer', 'File d\'attente vide', 'Очередь пуста']);
  String get lyricsCaps => _s(['LYRICS', 'बोल', 'LETRA', '歌詞', '가사', 'SONGTEXT', 'PAROLES', 'ТЕКСТ']);
  String get nothingPlaying => _s(['Nothing playing', 'कुछ नहीं चल रहा', 'Nada en reproducción', '再生中の曲はありません', '재생 중인 곡 없음', 'Nichts wird abgespielt', 'Aucune lecture', 'Ничего не играет']);
  String get pickASong => _s(['Pick a song from your library', 'अपनी लाइब्रेरी से कोई गाना चुनें', 'Elige una canción de tu biblioteca', 'ライブラリから曲を選んでください', '라이브러리에서 곡을 선택하세요', 'Wähle einen Song aus deiner Bibliothek', 'Choisissez un titre dans votre bibliothèque', 'Выберите песню из библиотеки']);
  String get noLyricsInFile => _s(['No lyrics in this file.\nTurn on Online lyrics in Settings.', 'इस फ़ाइल में बोल नहीं हैं।\nसेटिंग्स में ऑनलाइन बोल चालू करें।', 'Este archivo no tiene letra.\nActiva la letra en línea en Ajustes.', 'この曲に歌詞がありません。\n設定でオンライン歌詞をオンに。', '이 파일에 가사가 없습니다.\n설정에서 온라인 가사를 켜세요.', 'Keine Songtexte in dieser Datei.\nOnline-Songtexte in den Einstellungen aktivieren.', 'Pas de paroles dans ce fichier.\nActivez les paroles en ligne dans Réglages.', 'В файле нет текста.\nВключите онлайн-тексты в настройках.']);
  String get lyricsOffline => _s(["Couldn't reach the lyrics service.\nCheck your internet connection.", 'बोल सेवा से संपर्क नहीं हो सका।\nअपना इंटरनेट कनेक्शन जाँचें।', 'No se pudo conectar al servicio.\nComprueba tu conexión a internet.', '歌詞サービスに接続できません。\nインターネット接続を確認してください。', '가사 서비스에 연결할 수 없습니다.\n인터넷 연결을 확인하세요.', 'Songtext-Dienst nicht erreichbar.\nPrüfe deine Internetverbindung.', 'Service de paroles injoignable.\nVérifiez votre connexion internet.', 'Сервис текстов недоступен.\nПроверьте подключение к интернету.']);
  String get noLyricsFound => _s(['No lyrics found for this track.', 'इस ट्रैक के बोल नहीं मिले।', 'No se encontró la letra.', 'この曲の歌詞は見つかりませんでした。', '이 곡의 가사를 찾을 수 없습니다.', 'Keine Songtexte gefunden.', 'Aucune parole trouvée.', 'Текст не найден.']);
  String get couldNotReadLyrics => _s(['Could not read lyrics', 'बोल पढ़े नहीं जा सके', 'No se pudo leer la letra', '歌詞を読み込めません', '가사를 읽을 수 없음', 'Songtexte nicht lesbar', 'Impossible de lire les paroles', 'Не удалось прочитать текст']);

  // --- Settings -----------------------------------------------------------
  String get appearance => _s(['Appearance', 'दिखावट', 'Apariencia', '外観', '모양', 'Darstellung', 'Apparence', 'Оформление']);
  String get themeAuto => _s(['Auto', 'स्वतः', 'Auto', '自動', '자동', 'Auto', 'Auto', 'Авто']);
  String get themeLight => _s(['Light', 'लाइट', 'Claro', 'ライト', '라이트', 'Hell', 'Clair', 'Светлая']);
  String get themeDark => _s(['Dark', 'डार्क', 'Oscuro', 'ダーク', '다크', 'Dunkel', 'Sombre', 'Тёмная']);
  String get materialYou => _s(['Material You', 'Material You', 'Material You', 'Material You', 'Material You', 'Material You', 'Material You', 'Material You']);
  String get materialYouSub => _s(['Use your wallpaper colors (Android 12+)', 'वॉलपेपर के रंग इस्तेमाल करें (Android 12+)', 'Usa los colores de tu fondo (Android 12+)', '壁紙の色を使用（Android 12以降）', '배경화면 색상 사용 (Android 12+)', 'Hintergrundfarben verwenden (Android 12+)', 'Couleurs de votre fond d\'écran (Android 12+)', 'Цвета обоев (Android 12+)']);
  String get language => _s(['Language', 'भाषा', 'Idioma', '言語', '언어', 'Sprache', 'Langue', 'Язык']);
  String get audio => _s(['Audio', 'ऑडियो', 'Audio', 'オーディオ', '오디오', 'Audio', 'Audio', 'Аудио']);
  String get equalizer => _s(['Equalizer', 'इक्वलाइज़र', 'Ecualizador', 'イコライザー', '이퀄라이저', 'Equalizer', 'Égaliseur', 'Эквалайзер']);
  String get equalizerSub => _s(['5-band EQ, presets, bass boost', '5-बैंड EQ, प्रीसेट, बेस बूस्ट', 'EQ de 5 bandas, presets, bass boost', '5バンドEQ・プリセット・低音ブースト', '5밴드 EQ, 프리셋, 베이스 부스트', '5-Band-EQ, Presets, Bassboost', 'EQ 5 bandes, presets, bass boost', '5-полосный EQ, пресеты, бас']);
  String get smoothTransitions => _s(['Smooth transitions', 'सहज ट्रांज़िशन', 'Transiciones suaves', 'スムーズな切り替え', '부드러운 전환', 'Sanfte Übergänge', 'Transitions douces', 'Плавные переходы']);
  String get smoothTransitionsSub => _s(['Gentle fade on play, pause and skip', 'चलाने, रोकने और स्किप पर हल्का फ़ेड', 'Fundido suave al reproducir, pausar y saltar', '再生・一時停止・スキップ時にフェード', '재생·일시정지·건너뛰기 시 페이드', 'Sanftes Ein-/Ausblenden', 'Fondu léger à la lecture, pause et saut', 'Мягкое затухание при управлении']);
  String get resumeOnBluetooth => _s(['Resume on Bluetooth', 'ब्लूटूथ पर फिर चलाएँ', 'Reanudar con Bluetooth', 'Bluetoothで再開', '블루투스 연결 시 재개', 'Bei Bluetooth fortsetzen', 'Reprendre en Bluetooth', 'Продолжать по Bluetooth']);
  String get resumeOnBluetoothSub => _s(['Auto-play when your headphones or car connect', 'हेडफ़ोन या कार कनेक्ट होने पर अपने आप चलाएँ', 'Reproducir al conectar auriculares o el coche', 'ヘッドホンや車の接続時に自動再生', '헤드폰·차량 연결 시 자동 재생', 'Auto-Wiedergabe bei Kopfhörer/Auto', 'Lecture auto à la connexion casque/voiture', 'Автовоспроизведение при подключении']);
  String get crossfade => _s(['Crossfade', 'क्रॉसफ़ेड', 'Fundido cruzado', 'クロスフェード', '크로스페이드', 'Crossfade', 'Fondu enchaîné', 'Кроссфейд']);
  String get off => _s(['Off', 'बंद', 'No', 'オフ', '꺼짐', 'Aus', 'Non', 'Выкл']);
  String get rescanLibrary => _s(['Rescan library', 'लाइब्रेरी फिर स्कैन करें', 'Reescanear biblioteca', 'ライブラリを再スキャン', '라이브러리 다시 검색', 'Bibliothek neu scannen', 'Réanalyser la bibliothèque', 'Пересканировать библиотеку']);
  String nSongsIndexed(int n) => _s(['$n songs indexed', '$n गाने सूचीबद्ध', '$n canciones indexadas', '$n曲を検出', '$n곡 색인됨', '$n Songs indiziert', '$n titres indexés', 'Найдено песен: $n']);
  String get scanning => _s(['Scanning…', 'स्कैन हो रहा है…', 'Escaneando…', 'スキャン中…', '검색 중…', 'Scanne…', 'Analyse…', 'Сканирование…']);
  String get lyricsFolder => _s(['Lyrics folder', 'बोल फ़ोल्डर', 'Carpeta de letras', '歌詞フォルダ', '가사 폴더', 'Songtext-Ordner', 'Dossier de paroles', 'Папка текстов']);
  String get onlineLyrics => _s(['Online lyrics', 'ऑनलाइन बोल', 'Letra en línea', 'オンライン歌詞', '온라인 가사', 'Online-Songtexte', 'Paroles en ligne', 'Онлайн-тексты']);
  String get onlineLyricsSub => _s(['Fetch missing lyrics from LRCLIB and save them for offline use', 'LRCLIB से बोल लाकर ऑफ़लाइन के लिए सहेजें', 'Descarga letras de LRCLIB y guárdalas sin conexión', 'LRCLIBから歌詞を取得しオフライン保存', 'LRCLIB에서 가사를 가져와 오프라인 저장', 'Songtexte von LRCLIB laden und offline speichern', 'Récupérer les paroles via LRCLIB (hors ligne ensuite)', 'Загрузка текстов из LRCLIB для офлайна']);
  String get about => _s(['About', 'परिचय', 'Acerca de', '情報', '정보', 'Über', 'À propos', 'О приложении']);
  String get privacy => _s(['Privacy', 'गोपनीयता', 'Privacidad', 'プライバシー', '개인정보', 'Datenschutz', 'Confidentialité', 'Конфиденциальность']);
  String get rescanning => _s(['Rescanning your library', 'लाइब्रेरी फिर स्कैन हो रही है', 'Reescaneando tu biblioteca', 'ライブラリを再スキャン中', '라이브러리 다시 검색 중', 'Bibliothek wird neu gescannt', 'Réanalyse de la bibliothèque', 'Библиотека сканируется заново']);
}
