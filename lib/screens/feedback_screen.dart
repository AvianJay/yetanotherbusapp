import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/app_routes.dart';
import '../core/auth_token_store.dart';
import '../core/feedback_service.dart';
import '../widgets/background_image_wrapper.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _feedbackService = FeedbackService();
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppController controller) async {
    if (_submitting) {
      return;
    }
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _feedbackService.submitFeedback(
        title: _titleController.text,
        content: _contentController.text,
      );
      _titleController.clear();
      _contentController.clear();
      formState.reset();
      messenger.showSnackBar(
        const SnackBar(content: Text('意見回饋已送出，感謝你幫助我們改進。')),
      );
    } on AuthTokenExpiredException {
      await controller.logoutAuth();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('登入已失效，請重新登入後再送出。')));
    } on FeedbackRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      final retryAfter = error.retryAfterSeconds;
      final message = retryAfter != null && retryAfter > 0
          ? '你已受到速率限制。'
          : error.message;
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final hasBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'feedback',
    );

    return BackgroundImageWrapper(
      pageKey: 'feedback',
      child: Scaffold(
        backgroundColor: hasBackgroundImage ? Colors.transparent : null,
        appBar: AppBar(title: const Text('意見回饋')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                // Card(
                //   child: Padding(
                //     padding: const EdgeInsets.all(18),
                //     child: Column(
                //       crossAxisAlignment: CrossAxisAlignment.start,
                //       children: [
                //         Text(
                //           '直接把你的想法丟給我們',
                //           style: Theme.of(context).textTheme.titleMedium,
                //         ),
                //         const SizedBox(height: 8),
                //         const Text(
                //           '可以回報 bug、提出功能需求，或告訴我們哪裡用起來卡卡的。標題上限 100 字，內文上限 4000 字。',
                //         ),
                //         const SizedBox(height: 8),
                //         const Text('送出前請避免貼上敏感個資、密碼或完整付款資訊。'),
                //       ],
                //     ),
                //   ),
                // ),
                const SizedBox(height: 12),
                if (!controller.isAuthenticated) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '請先登入',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.account);
                            },
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('前往登入'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _titleController,
                              enabled: !_submitting,
                              maxLength: 100,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '標題',
                                hintText: '例如：收藏站牌同步失敗',
                              ),
                              validator: (value) {
                                final cleaned = (value ?? '').trim();
                                if (cleaned.isEmpty) {
                                  return '請輸入標題';
                                }
                                if (cleaned.length > 100) {
                                  return '標題最多 100 個字';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _contentController,
                              enabled: !_submitting,
                              maxLength: 4000,
                              minLines: 8,
                              maxLines: 14,
                              decoration: const InputDecoration(
                                labelText: '內容',
                                alignLabelWithHint: true,
                                hintText: '描述發生了什麼、你原本預期看到什麼，以及重現步驟。',
                              ),
                              validator: (value) {
                                final cleaned = (value ?? '').trim();
                                if (cleaned.isEmpty) {
                                  return '請輸入內容';
                                }
                                if (cleaned.length > 4000) {
                                  return '內文最多 4000 個字';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () => _submit(controller),
                              icon: _submitting
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(_submitting ? '送出中…' : '送出回饋'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final raw = '$error';
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  if (raw.startsWith('Invalid argument')) {
    return '送出資料格式不正確。';
  }
  return raw;
}
