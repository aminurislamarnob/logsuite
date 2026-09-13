import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/common.dart';

/// Camera or gallery, asked the same way from every "scan" button in the
/// app. Returns true for the camera, false for the gallery, null when
/// dismissed.
Future<bool?> showDocumentSourceSheet(BuildContext context) {
  return brandSheet<bool>(
    context: context,
    builder: (sheetContext) => SheetScaffold(
      title: 'Scan a document',
      child: TileColumn(
        children: [
          BrandTile(
            leading: const AppIcon(AppIcons.camera),
            title: const Text('Take a photo'),
            subtitle: const Text('A bill, receipt or note'),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          BrandTile(
            leading: const AppIcon(AppIcons.gallery),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    ),
  );
}
