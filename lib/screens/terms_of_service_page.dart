import 'package:flutter/material.dart';

import '../core/legal_document_service.dart';
import 'legal_markdown_page.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  static final LegalDocumentService _service = LegalDocumentService();

  @override
  Widget build(BuildContext context) {
    return LegalMarkdownPage(
      title: '服務條款',
      loadDocument: _service.fetchTermsOfService,
    );
  }
}