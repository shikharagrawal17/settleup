import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/group_member.dart';
import '../services/gemini_service.dart';
import '../utils/ocr_helper.dart';

/// Modern dialog to configure Google Gemini API Key.
Future<void> showGeminiApiKeyDialog(BuildContext context) async {
  final currentKey = await GeminiService.getApiKey() ?? '';
  final controller = TextEditingController(text: currentKey);
  bool isSaving = false;
  String? statusMessage;
  bool isSuccess = false;

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Google Gemini AI',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Power your receipts and expense splits with Google Gemini 1.5 Flash.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Google AI Studio API Key',
                  hintText: 'AIzaSy...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => controller.clear(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Get Free Key from Google AI Studio', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final uri = Uri.parse('https://aistudio.google.com/app/apikey');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              if (statusMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                        size: 16,
                        color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    final key = controller.text.trim();
                    if (key.isEmpty) {
                      await GeminiService.clearApiKey();
                      if (context.mounted) Navigator.pop(context);
                      return;
                    }

                    setState(() {
                      isSaving = true;
                      statusMessage = null;
                    });

                    await GeminiService.setApiKey(key);

                    setState(() {
                      isSaving = false;
                      isSuccess = true;
                      statusMessage = 'API key saved successfully!';
                    });

                    await Future.delayed(const Duration(milliseconds: 700));
                    if (context.mounted) Navigator.pop(context);
                  },
            child: isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Key'),
          ),
        ],
      ),
    ),
  );
}

/// Bottom sheet to choose between Camera, Gallery, and Gemini Settings for receipt OCR.
Future<void> showReceiptScanOptionsSheet(
  BuildContext context, {
  required Function(OcrResult result) onScanned,
}) async {
  final hasKey = (await GeminiService.getApiKey() ?? '').isNotEmpty;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.document_scanner_rounded, color: Colors.blueAccent, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Bill or Receipt',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'AI reads total, merchant name & line items',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.vpn_key_outlined,
                  color: hasKey ? Colors.green : Colors.orange,
                  size: 20,
                ),
                tooltip: hasKey ? 'Gemini Key Configured' : 'Configure Gemini Key',
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await showGeminiApiKeyDialog(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.camera_alt_outlined, color: Colors.indigo),
            ),
            title: const Text('Take Photo (Camera)', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Point camera directly at paper invoice'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              _executeScan(context, ImageSource.camera, onScanned);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.photo_library_outlined, color: Colors.teal),
            ),
            title: const Text('Choose from Photos / Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Select screenshot or downloaded receipt'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              _executeScan(context, ImageSource.gallery, onScanned);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

Future<void> _executeScan(
  BuildContext context,
  ImageSource source,
  Function(OcrResult result) onScanned,
) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 12),
          Text('Processing receipt with Google AI...'),
        ],
      ),
      duration: Duration(seconds: 4),
    ),
  );

  final result = await OcrHelper.scanReceipt(source: source);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  if (result != null) {
    onScanned(result);
    final providerText = result.provider ?? 'AI';
    final desc = result.description ?? 'Receipt';
    final amt = result.amount != null ? '₹${result.amount!.toStringAsFixed(2)}' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade800,
        content: Text('✓ Scanned with $providerText: $desc $amt'),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not extract details from receipt. Please verify image or API key.'),
      ),
    );
  }
}

/// Conversational Smart AI Expense Split Assistant sheet
Future<void> showSmartSplitSheet(
  BuildContext context, {
  required List<GroupMember> members,
  required Function(GeminiSplitPlan plan) onPlanReady,
}) async {
  final textController = TextEditingController();
  bool isProcessing = false;
  String? errorMessage;

  final sampleChips = [
    'Dinner ₹1800 with everyone, I paid',
    'Uber ₹420 split with Aman, he paid',
    'Groceries ₹1250: Shikhar ₹750, Priya ₹500',
  ];

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (context, setState) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF9B51E0)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart AI Split',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Powered by Google Gemini 1.5 Flash',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined, size: 20, color: Colors.black54),
                    tooltip: 'Gemini API Key',
                    onPressed: () => showGeminiApiKeyDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Type or speak what happened:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: textController,
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Shikhar paid ₹1500 for team pizza with Aman and Rahul...',
                  hintStyle: const TextStyle(color: Colors.black38),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Examples:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: sampleChips.map((chip) {
                  return ActionChip(
                    label: Text(chip, style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onPressed: () {
                      setState(() {
                        textController.text = chip;
                      });
                    },
                  );
                }).toList(),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    isProcessing ? 'Analyzing with Gemini...' : 'Auto-Generate Split',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final text = textController.text.trim();
                          if (text.isEmpty) {
                            setState(() => errorMessage = 'Please enter expense details');
                            return;
                          }

                          setState(() {
                            isProcessing = true;
                            errorMessage = null;
                          });

                          try {
                            final plan = await GeminiService.parseNaturalLanguageExpense(
                              prompt: text,
                              members: members,
                            );

                            if (context.mounted) {
                              Navigator.pop(sheetCtx);
                              onPlanReady(plan);
                            }
                          } catch (e) {
                            setState(() {
                              isProcessing = false;
                              if (e.toString().contains('API key is not configured')) {
                                errorMessage = 'Gemini API key is required. Tap the key icon at top-right.';
                              } else {
                                errorMessage = 'Gemini error: ${e.toString()}';
                              }
                            });
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
