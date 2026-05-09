import 'package:flutter/material.dart';

import '../core/legal_document_service.dart';
import 'legal_markdown_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static final LegalDocumentService _service = LegalDocumentService();

  @override
  Widget build(BuildContext context) {
    return LegalMarkdownPage(
      title: '隱私權政策',
      loadDocument: _service.fetchPrivacyPolicy,
    );
  }
}