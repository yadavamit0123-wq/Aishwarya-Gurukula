import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:webinar/app/models/ai_assistant_model.dart';
import 'package:webinar/app/services/user_service/ai_assistant_service.dart';
import 'package:webinar/common/common.dart';
import 'package:webinar/common/components.dart';
import 'package:webinar/common/enums/error_enum.dart';
import 'package:webinar/common/utils/ai_assistant_config.dart';
import 'package:webinar/config/colors.dart';
import 'package:webinar/config/styles.dart';

class AiAssistantPage extends StatefulWidget {
  static const String pageName = '/ai-assistant';

  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final String? imageUrl;
  final String? localImagePath;

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.imageUrl,
    this.localImagePath,
  });
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  AiAssistantUsage? _usage;
  bool _loadingUsage = true;
  bool _sending = false;

  String _scope = 'general';
  AiAssistantCourseItem? _selectedCourse;
  AiAssistantSubjectItem? _selectedSubject;
  List<AiAssistantCourseItem> _courses = [];
  List<AiAssistantSubjectItem> _subjects = [];

  String? _conversationId;
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speech = SpeechToText();
  final ImagePicker _imagePicker = ImagePicker();

  bool _speechReady = false;
  bool _isListening = false;
  File? _pendingImage;

  @override
  void initState() {
    super.initState();
    _initScope();
    _bootstrap();
    _initSpeech();
    _inputController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  void _initScope() {
    if (AiAssistantConfig.allowTextSearch) {
      _scope = 'general';
    } else if (AiAssistantConfig.allowCourseSearch) {
      _scope = 'course';
    } else if (AiAssistantConfig.allowSubjectSearch) {
      _scope = 'subject';
    }
  }

  Future<void> _bootstrap() async {
    await _refreshUsage();
    if (AiAssistantConfig.allowCourseSearch || AiAssistantConfig.allowSubjectSearch) {
      _courses = await AiAssistantService.getCourses();
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshUsage() async {
    setState(() => _loadingUsage = true);
    _usage = await AiAssistantService.getUsage();
    if (mounted) setState(() => _loadingUsage = false);
  }

  Future<void> _onCourseChanged(AiAssistantCourseItem? course) async {
    setState(() {
      _selectedCourse = course;
      _selectedSubject = null;
      _subjects = [];
    });
    if (course != null && _scope == 'subject') {
      _subjects = await AiAssistantService.getSubjects(course.id);
      if (mounted) setState(() {});
    }
  }

  bool get _canSend {
    if (_sending || _loadingUsage) return false;
    if (_usage == null || !_usage!.aiEnabledForUser) return false;
    if (_usage!.searchesRemaining <= 0) return false;
    final hasText = _inputController.text.trim().isNotEmpty;
    final hasImage = _pendingImage != null;
    if (!hasText && !hasImage) return false;
    if (_scope == 'course' && _selectedCourse == null) return false;
    if (_scope == 'subject' && (_selectedCourse == null || _selectedSubject == null)) {
      return false;
    }
    return true;
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (!_speechReady) {
      showSnackBar(ErrorEnum.error, 'Voice input is not available on this device.');
      return;
    }
    if (mounted) setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        });
      },
      listenMode: ListenMode.dictation,
      partialResults: true,
    );
  }

  Future<File?> _compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final target = '${dir.path}/ai_search_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        quality: 82,
        minWidth: 1280,
        minHeight: 1280,
      );
      if (result != null) return File(result.path);
    } catch (_) {}
    return file;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
      if (picked == null) return;
      final compressed = await _compressImage(File(picked.path));
      if (mounted) setState(() => _pendingImage = compressed);
    } catch (_) {
      showSnackBar(ErrorEnum.error, 'Could not pick image.');
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: green77()),
                  title: const Text('Photo library'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined, color: green77()),
                  title: const Text('Camera / screenshot'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<({String? base64, String mime})> _encodePendingImageFromFile(File? file) async {
    if (file == null) return (base64: null, mime: 'image/jpeg');
    final bytes = await file.readAsBytes();
    final mime = file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    return (base64: base64Encode(bytes), mime: mime);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;

    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }

    var query = _inputController.text.trim();
    final imagePath = _pendingImage?.path;
    if (query.isEmpty && _pendingImage != null) {
      query = 'Please explain this image and help me with my study question.';
    }

    _inputController.clear();
    final pending = _pendingImage;
    setState(() {
      _pendingImage = null;
      _messages.add(_ChatMessage(
        isUser: true,
        text: query,
        localImagePath: imagePath,
      ));
      _sending = true;
    });
    _scrollToBottom();

    await _refreshUsage();

    final encoded = await _encodePendingImageFromFile(pending);
    final response = await AiAssistantService.search(
      query: query,
      scope: _scope,
      courseId: _selectedCourse?.id,
      subjectId: _selectedSubject?.id,
      conversationId: _conversationId,
      imageBase64: encoded.base64,
      imageMime: encoded.mime,
    );

    if (!mounted) return;

    if (response.result != null) {
      _conversationId = response.result!.conversationId ?? _conversationId;
      if (response.result!.searchesRemaining != null) {
        _usage = AiAssistantUsage(
          searchesRemaining: response.result!.searchesRemaining!,
          searchesLimit: _usage?.searchesLimit ?? 0,
          imagesRemaining: _usage?.imagesRemaining ?? 0,
          imagesLimit: _usage?.imagesLimit ?? 0,
          period: _usage?.period,
          resetsAt: _usage?.resetsAt,
          aiEnabledForUser: _usage?.aiEnabledForUser ?? true,
        );
      } else {
        await _refreshUsage();
      }
      setState(() {
        _messages.add(_ChatMessage(isUser: false, text: response.result!.answer));
        _sending = false;
      });
    } else {
      await _refreshUsage();
      setState(() => _sending = false);
      showSnackBar(ErrorEnum.error, response.errorMessage);
    }
    _scrollToBottom();
  }

  Future<void> _generateImage() async {
    if (!AiAssistantConfig.allowImageGenerate) return;
    if (_usage == null || _usage!.imagesRemaining <= 0) {
      showSnackBar(ErrorEnum.error, 'Image quota exhausted for this period.');
      return;
    }
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty) {
      showSnackBar(ErrorEnum.error, 'Enter a prompt to generate an image.');
      return;
    }

    setState(() => _sending = true);
    await _refreshUsage();

    final response = await AiAssistantService.generateImage(
      prompt: prompt,
      courseId: _selectedCourse?.id,
    );

    if (!mounted) return;

    if (response.result != null && response.result!.imageUrl.isNotEmpty) {
      if (response.result!.imagesRemaining != null) {
        _usage = AiAssistantUsage(
          searchesRemaining: _usage?.searchesRemaining ?? 0,
          searchesLimit: _usage?.searchesLimit ?? 0,
          imagesRemaining: response.result!.imagesRemaining!,
          imagesLimit: _usage?.imagesLimit ?? 0,
          period: _usage?.period,
          resetsAt: _usage?.resetsAt,
          aiEnabledForUser: _usage?.aiEnabledForUser ?? true,
        );
      } else {
        await _refreshUsage();
      }
      setState(() {
        _messages.add(_ChatMessage(isUser: true, text: prompt));
        _messages.add(_ChatMessage(isUser: false, text: 'Generated image', imageUrl: response.result!.imageUrl));
        _inputController.clear();
        _sending = false;
      });
    } else {
      await _refreshUsage();
      setState(() => _sending = false);
      showSnackBar(ErrorEnum.error, response.errorMessage);
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    _speech.stop();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return directionality(
      child: Scaffold(
        appBar: appbar(title: 'AI Assistant'),
        body: Column(
          children: [
            if (_loadingUsage)
              const LinearProgressIndicator(minHeight: 2)
            else
              _UsageBanner(usage: _usage),
            _ScopeBar(
              scope: _scope,
              onScopeChanged: (value) async {
                setState(() => _scope = value);
                if (value == 'subject' && _selectedCourse != null) {
                  _subjects = await AiAssistantService.getSubjects(_selectedCourse!.id);
                  if (mounted) setState(() {});
                }
              },
              courses: _courses,
              subjects: _subjects,
              selectedCourse: _selectedCourse,
              selectedSubject: _selectedSubject,
              onCourseChanged: _onCourseChanged,
              onSubjectChanged: (s) => setState(() => _selectedSubject = s),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: padding(horizontal: 24),
                        child: Text(
                          'Ask anything about your courses. Answers use your enrolled content when you pick a course or chapter.',
                          style: style14Regular().copyWith(color: greyA5),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: padding(horizontal: 16, vertical: 12),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_sending && index == _messages.length) {
                          return _Bubble(
                            isUser: false,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: green77()),
                            ),
                          );
                        }
                        final msg = _messages[index];
                        return _Bubble(
                          isUser: msg.isUser,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.text.isNotEmpty) Text(msg.text, style: style14Regular()),
                              if (msg.localImagePath != null) ...[
                                space(8),
                                ClipRRect(
                                  borderRadius: borderRadius(radius: 8),
                                  child: Image.file(
                                    File(msg.localImagePath!),
                                    width: getSize().width * .65,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                              if (msg.imageUrl != null) ...[
                                space(8),
                                ClipRRect(
                                  borderRadius: borderRadius(radius: 8),
                                  child: CachedNetworkImage(
                                    imageUrl: msg.imageUrl!,
                                    width: getSize().width * .65,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_pendingImage != null)
              Padding(
                padding: padding(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: borderRadius(radius: 8),
                      child: Image.file(
                        _pendingImage!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    space(0, width: 8),
                    Expanded(
                      child: Text(
                        'Image attached — add a question or tap send',
                        style: style12Regular().copyWith(color: greyA5),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : () => setState(() => _pendingImage = null),
                      icon: Icon(Icons.close, color: greyA5, size: 20),
                    ),
                  ],
                ),
              ),
            _InputBar(
              controller: _inputController,
              canSend: _canSend,
              canAttachImage: AiAssistantConfig.allowImageSearch && !_sending,
              canGenerateImage: AiAssistantConfig.allowImageGenerate &&
                  (_usage?.imagesRemaining ?? 0) > 0 &&
                  !_sending,
              isListening: _isListening,
              onAttachImage: _showImageSourceSheet,
              onToggleMic: _toggleListening,
              onSend: _send,
              onGenerateImage: _generateImage,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBanner extends StatelessWidget {
  final AiAssistantUsage? usage;

  const _UsageBanner({required this.usage});

  @override
  Widget build(BuildContext context) {
    if (usage == null) {
      return Padding(
        padding: padding(horizontal: 16, vertical: 8),
        child: Text('Unable to load AI usage.', style: style12Regular().copyWith(color: greyA5)),
      );
    }
    return Container(
      width: double.infinity,
      padding: padding(horizontal: 16, vertical: 10),
      color: green77().withOpacity(.12),
      child: Text(
        'Searches left: ${usage!.searchesRemaining}/${usage!.searchesLimit}'
        '${usage!.imagesLimit > 0 ? ' · Images left: ${usage!.imagesRemaining}/${usage!.imagesLimit}' : ''}',
        style: style12Regular(),
      ),
    );
  }
}

class _ScopeBar extends StatelessWidget {
  final String scope;
  final ValueChanged<String> onScopeChanged;
  final List<AiAssistantCourseItem> courses;
  final List<AiAssistantSubjectItem> subjects;
  final AiAssistantCourseItem? selectedCourse;
  final AiAssistantSubjectItem? selectedSubject;
  final ValueChanged<AiAssistantCourseItem?> onCourseChanged;
  final ValueChanged<AiAssistantSubjectItem?> onSubjectChanged;

  const _ScopeBar({
    required this.scope,
    required this.onScopeChanged,
    required this.courses,
    required this.subjects,
    required this.selectedCourse,
    required this.selectedSubject,
    required this.onCourseChanged,
    required this.onSubjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scopes = <String, String>{};
    if (AiAssistantConfig.allowTextSearch) scopes['general'] = 'General';
    if (AiAssistantConfig.allowCourseSearch) scopes['course'] = 'Course';
    if (AiAssistantConfig.allowSubjectSearch) scopes['subject'] = 'Chapter';

    return Padding(
      padding: padding(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scopes.length > 1)
            DropdownButtonFormField<String>(
              value: scopes.containsKey(scope) ? scope : scopes.keys.first,
              decoration: const InputDecoration(labelText: 'Search scope', isDense: true),
              items: scopes.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onScopeChanged(v);
              },
            ),
          if (scope == 'course' || scope == 'subject') ...[
            space(8),
            DropdownButtonFormField<AiAssistantCourseItem>(
              value: selectedCourse,
              decoration: const InputDecoration(labelText: 'Course', isDense: true),
              items: courses
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.title, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: onCourseChanged,
            ),
          ],
          if (scope == 'subject') ...[
            space(8),
            DropdownButtonFormField<AiAssistantSubjectItem>(
              value: selectedSubject,
              decoration: const InputDecoration(labelText: 'Chapter', isDense: true),
              items: subjects
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.title, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: onSubjectChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isUser;
  final Widget child;

  const _Bubble({required this.isUser, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: padding(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(maxWidth: getSize().width * .82),
        decoration: BoxDecoration(
          color: isUser ? green77().withOpacity(.15) : greyF8,
          borderRadius: borderRadius(radius: 12),
        ),
        child: child,
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend;
  final bool canAttachImage;
  final bool canGenerateImage;
  final bool isListening;
  final VoidCallback onAttachImage;
  final VoidCallback onToggleMic;
  final VoidCallback onSend;
  final VoidCallback onGenerateImage;

  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.canAttachImage,
    required this.canGenerateImage,
    required this.isListening,
    required this.onAttachImage,
    required this.onToggleMic,
    required this.onSend,
    required this.onGenerateImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (canAttachImage)
              IconButton(
                onPressed: onAttachImage,
                icon: Icon(Icons.add_photo_alternate_outlined, color: green77()),
                tooltip: 'Upload photo or screenshot',
              ),
            if (canGenerateImage)
              IconButton(
                onPressed: onGenerateImage,
                icon: Icon(Icons.auto_awesome_outlined, color: green77()),
                tooltip: 'Generate image',
              ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: isListening ? 'Listening… speak your question' : 'Ask or attach a screenshot…',
                  filled: true,
                  fillColor: isListening ? green77().withOpacity(.08) : greyF8,
                  border: OutlineInputBorder(
                    borderRadius: borderRadius(radius: 12),
                    borderSide: isListening
                        ? BorderSide(color: green77().withOpacity(.5))
                        : BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    onPressed: onToggleMic,
                    icon: Icon(
                      isListening ? Icons.mic : Icons.mic_none_outlined,
                      color: isListening ? Colors.red : green77(),
                    ),
                    tooltip: isListening ? 'Stop voice input' : 'Voice search',
                  ),
                ),
                onSubmitted: (_) {
                  if (canSend) onSend();
                },
              ),
            ),
            IconButton(
              onPressed: canSend ? onSend : null,
              icon: Icon(Icons.send_rounded, color: canSend ? green77() : greyA5),
            ),
          ],
        ),
      ),
    );
  }
}
