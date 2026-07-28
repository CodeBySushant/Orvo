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
  en('English', Locale('en'), '🇺🇸'),
  hi('हिन्दी', Locale('hi'), '🇮🇳'),
  es('Español', Locale('es'), '🇪🇸'),
  ja('日本語', Locale('ja'), '🇯🇵'),
  ko('한국어', Locale('ko'), '🇰🇷'),
  de('Deutsch', Locale('de'), '🇩🇪'),
  fr('Français', Locale('fr'), '🇫🇷'),
  ru('Русский', Locale('ru'), '🇷🇺');

  const AppLanguage(this.nativeName, this.locale, this.flag);
  final String nativeName;
  final Locale locale;
  final String flag;
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
  // REDESIGN v3 (mockup home): hero cards + new shelf titles.
  String get favorites => _s(['Favorites', 'पसंदीदा', 'Favoritos', 'お気に入り', '즐겨찾기', 'Favoriten', 'Favoris', 'Избранное']);
  String get shuffle => _s(['Shuffle', 'शफ़ल', 'Aleatorio', 'シャッフル', '셔플', 'Zufällig', 'Aléatoire', 'Перемешать']);
  String get myPlaylist => _s(['My Playlist', 'मेरी प्लेलिस्ट', 'Mi playlist', 'マイプレイリスト', '내 재생목록', 'Meine Playlist', 'Ma playlist', 'Мой плейлист']);
  String get lastAdded => _s(['Last Added', 'हाल में जोड़े गए', 'Añadidos recientemente', '最近追加', '최근 추가', 'Zuletzt hinzugefügt', 'Derniers ajouts', 'Недавно добавленные']);
  String get mostPlayed => _s(['Most Played', 'सबसे ज़्यादा चलाए गए', 'Más reproducidos', 'よく再生する曲', '자주 재생한 곡', 'Meistgespielt', 'Les plus écoutés', 'Часто прослушиваемые']);
  String get recommendArtists => _s(['Recommend Artists', 'सुझाए गए कलाकार', 'Artistas recomendados', 'おすすめアーティスト', '추천 아티스트', 'Empfohlene Künstler', 'Artistes recommandés', 'Рекомендуемые исполнители']);
  String get recommendAlbums => _s(['Recommend Albums', 'सुझाए गए एल्बम', 'Álbumes recomendados', 'おすすめアルバム', '추천 앨범', 'Empfohlene Alben', 'Albums recommandés', 'Рекомендуемые альбомы']);
  String nSongsExact(int n) => n == 1
      ? '1 ${_s(['Song', 'गाना', 'canción', '曲', '곡', 'Song', 'titre', 'песня'])}'
      : nSongs(n);
  // REDESIGN v3.1 (mockup sidebar).
  String get themes => _s(['Themes', 'थीम', 'Temas', 'テーマ', '테마', 'Themes', 'Thèmes', 'Темы']);
  String get sleepTimer => _s(['Sleep Timer', 'स्लीप टाइमर', 'Temporizador', 'スリープタイマー', '수면 타이머', 'Sleep-Timer', 'Minuterie de veille', 'Таймер сна']);
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
  String get excludedFolders => _s(['Excluded folders', 'बाहर रखे फ़ोल्डर', 'Carpetas excluidas', '除外フォルダ', '제외된 폴더', 'Ausgeschlossene Ordner', 'Dossiers exclus', 'Исключённые папки']);
  String get excludedFoldersSub => _s(['Hide voice notes, recordings and other folders', 'वॉइस नोट, रिकॉर्डिंग व अन्य फ़ोल्डर छिपाएँ', 'Oculta notas de voz, grabaciones y más', 'ボイスメモや録音などを非表示', '음성 메모·녹음 등 숨기기', 'Sprachnotizen, Aufnahmen u. a. ausblenden', 'Masquer notes vocales, enregistrements…', 'Скрыть голосовые заметки и записи']);
  String get excludedFoldersExplainer => _s(['Folders switched off are hidden everywhere in Orvo — library, search, shuffle and stats. Your files stay on the device untouched; switch a folder back on any time.', 'बंद किए गए फ़ोल्डर Orvo में हर जगह छिप जाते हैं — लाइब्रेरी, खोज, शफ़ल और आँकड़े। आपकी फ़ाइलें डिवाइस पर सुरक्षित रहती हैं; कभी भी वापस चालू करें।', 'Las carpetas desactivadas se ocultan en todo Orvo: biblioteca, búsqueda, aleatorio y estadísticas. Tus archivos permanecen intactos; reactívalas cuando quieras.', 'オフにしたフォルダはOrvo全体（ライブラリ・検索・シャッフル・統計）で非表示になります。ファイルは端末に残ります。いつでも元に戻せます。', '끈 폴더는 Orvo 전체(라이브러리·검색·셔플·통계)에서 숨겨집니다. 파일은 기기에 그대로 남으며 언제든 다시 켤 수 있습니다.', 'Deaktivierte Ordner werden überall in Orvo ausgeblendet — Bibliothek, Suche, Shuffle und Statistiken. Deine Dateien bleiben unangetastet; jederzeit wieder aktivierbar.', 'Les dossiers désactivés sont masqués partout dans Orvo — bibliothèque, recherche, aléatoire et statistiques. Vos fichiers restent intacts ; réactivez-les à tout moment.', 'Отключённые папки скрываются во всём Orvo — библиотека, поиск, перемешивание и статистика. Файлы остаются на устройстве; включить обратно можно в любой момент.']);
  String get rescanning => _s(['Rescanning your library', 'लाइब्रेरी फिर स्कैन हो रही है', 'Reescaneando tu biblioteca', 'ライブラリを再スキャン中', '라이브러리 다시 검색 중', 'Bibliothek wird neu gescannt', 'Réanalyse de la bibliothèque', 'Библиотека сканируется заново']);
  // FEATURE (help): Settings → Help section (FAQ, legal docs, version).
  String get help => _s(['Help', 'सहायता', 'Ayuda', 'ヘルプ', '도움말', 'Hilfe', 'Aide', 'Помощь']);
  String get faq => _s(['FAQ', 'सामान्य प्रश्न', 'Preguntas frecuentes', 'よくある質問', '자주 묻는 질문', 'FAQ', 'FAQ', 'Вопросы и ответы']);
  String get faqSub => _s(['Answers to common questions', 'आम सवालों के जवाब', 'Respuestas a preguntas comunes', 'よくある質問への回答', '자주 묻는 질문에 대한 답변', 'Antworten auf häufige Fragen', 'Réponses aux questions fréquentes', 'Ответы на частые вопросы']);
  String get privacyPolicy => _s(['Privacy policy', 'गोपनीयता नीति', 'Política de privacidad', 'プライバシーポリシー', '개인정보 처리방침', 'Datenschutzerklärung', 'Politique de confidentialité', 'Политика конфиденциальности']);
  String get termsOfUse => _s(['Terms of use', 'उपयोग की शर्तें', 'Términos de uso', '利用規約', '이용약관', 'Nutzungsbedingungen', 'Conditions d\'utilisation', 'Условия использования']);
  // FEATURE (backgrounds): wallpaper-style app backgrounds.
  String get backgrounds => _s(['Backgrounds', 'बैकग्राउंड', 'Fondos', '背景', '배경', 'Hintergründe', 'Fonds d\'écran', 'Фоны']);
  String get backgroundsNote => _s(['Set a wallpaper behind the whole app. Background themes use the dark look so everything stays readable.', 'पूरे ऐप के पीछे वॉलपेपर लगाएँ। पठनीयता के लिए बैकग्राउंड थीम डार्क रूप इस्तेमाल करती हैं।', 'Pon un fondo detrás de toda la app. Los fondos usan el aspecto oscuro para que todo sea legible.', 'アプリ全体の背景に壁紙を設定します。読みやすさのため背景テーマはダーク表示になります。', '앱 전체 뒤에 배경화면을 설정합니다. 가독성을 위해 배경 테마는 다크 모드로 표시됩니다.', 'Lege ein Hintergrundbild hinter die ganze App. Hintergrund-Themes nutzen den dunklen Look für gute Lesbarkeit.', 'Placez un fond d\'écran derrière toute l\'app. Les fonds utilisent le mode sombre pour rester lisibles.', 'Установите обои позади всего приложения. Для читаемости фоновые темы используют тёмный вид.']);
  String get noBackground => _s(['None', 'कोई नहीं', 'Ninguno', 'なし', '없음', 'Keine', 'Aucun', 'Нет']);
  // FEATURE (app icon): selectable launcher icon.
  String get appIcon => _s(['App icon', 'ऐप आइकन', 'Icono de la app', 'アプリアイコン', '앱 아이콘', 'App-Symbol', 'Icône de l\'app', 'Значок приложения']);
  String get appIconSub => _s(['Choose the icon shown on your home screen', 'होम स्क्रीन पर दिखने वाला आइकन चुनें', 'Elige el icono de tu pantalla de inicio', 'ホーム画面に表示するアイコンを選択', '홈 화면에 표시할 아이콘 선택', 'Symbol für den Startbildschirm wählen', 'Choisissez l\'icône de l\'écran d\'accueil', 'Выберите значок на главном экране']);
  String get appIconNote => _s(['Pick a look for Orvo on your home screen. Your launcher may take a few seconds — or a visit to the home screen — to show the new icon.', 'होम स्क्रीन पर Orvo का रूप चुनें। नया आइकन दिखने में लॉन्चर को कुछ सेकंड लग सकते हैं।', 'Elige el aspecto de Orvo en tu pantalla de inicio. El lanzador puede tardar unos segundos en mostrar el nuevo icono.', 'ホーム画面でのOrvoの見た目を選べます。新しいアイコンの反映には数秒かかることがあります。', '홈 화면에서 Orvo의 모습을 선택하세요. 새 아이콘이 표시되기까지 몇 초 걸릴 수 있습니다.', 'Wähle das Aussehen von Orvo auf dem Startbildschirm. Der Launcher braucht ggf. einige Sekunden für das neue Symbol.', 'Choisissez l\'apparence d\'Orvo sur l\'écran d\'accueil. Le lanceur peut mettre quelques secondes à afficher la nouvelle icône.', 'Выберите вид Orvo на главном экране. Новый значок может появиться через несколько секунд.']);
  String get appIconApplied => _s(['Icon applied — your home screen will update shortly', 'आइकन लागू — होम स्क्रीन जल्द अपडेट होगी', 'Icono aplicado: la pantalla de inicio se actualizará en breve', 'アイコンを適用しました。まもなくホーム画面に反映されます', '아이콘이 적용되었습니다. 곧 홈 화면에 반영됩니다', 'Symbol übernommen — der Startbildschirm aktualisiert sich gleich', 'Icône appliquée — l\'écran d\'accueil sera bientôt mis à jour', 'Значок применён — главный экран скоро обновится']);
  String get appIconFailed => _s(['Couldn\'t change the icon on this device', 'इस डिवाइस पर आइकन नहीं बदला जा सका', 'No se pudo cambiar el icono en este dispositivo', 'この端末ではアイコンを変更できませんでした', '이 기기에서는 아이콘을 변경할 수 없습니다', 'Symbol konnte auf diesem Gerät nicht geändert werden', 'Impossible de changer l\'icône sur cet appareil', 'Не удалось изменить значок на этом устройстве']);
  String get version => _s(['Version', 'संस्करण', 'Versión', 'バージョン', '버전', 'Version', 'Version', 'Версия']);
}
