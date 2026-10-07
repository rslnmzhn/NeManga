import 'package:flutter/material.dart';
import '../models/reader_models.dart';

class ReaderSettingsSheet extends StatefulWidget {
  final ReaderSettings settings;
  final int totalPages;
  final int currentPage;
  final ValueChanged<ReaderSettings> onSettingsChanged;
  final ValueChanged<int> onPageJump;

  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.totalPages,
    required this.currentPage,
    required this.onSettingsChanged,
    required this.onPageJump,
  });

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _current;
  final TextEditingController _jumpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.settings;
    _jumpController.text = (widget.currentPage + 1).toString();
  }

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  void _update(ReaderSettings newSettings) {
    setState(() {
      _current = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181B20) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Настройки читалки',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Режим чтения
            const Text(
              'Режим чтения и свайпы',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildModeChoice(
                  label: 'Вебтун (лента)',
                  icon: Icons.view_day_outlined,
                  mode: ReaderMode.webtoon,
                ),
                _buildModeChoice(
                  label: 'Свайп вверх/вниз',
                  icon: Icons.swap_vert,
                  mode: ReaderMode.verticalPage,
                ),
                _buildModeChoice(
                  label: 'Манга (RTL)',
                  icon: Icons.keyboard_double_arrow_left,
                  mode: ReaderMode.horizontalRtl,
                ),
                _buildModeChoice(
                  label: 'Комикс (LTR)',
                  icon: Icons.keyboard_double_arrow_right,
                  mode: ReaderMode.horizontalLtr,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Подгонка изображения
            const Text(
              'Масштаб страницы',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildFitOption(
                    label: 'По ширине',
                    fit: ImageFit.fitWidth,
                    icon: Icons.fit_screen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFitOption(
                    label: 'Целиком',
                    fit: ImageFit.contain,
                    icon: Icons.fullscreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFitOption(
                    label: 'По высоте',
                    fit: ImageFit.fitHeight,
                    icon: Icons.height,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Навигация по тапу
            const Text(
              'Управление нажатием (Тапы)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Перелистывать по краям экрана'),
              subtitle: const Text('Тап по краю — смена страницы'),
              value: _current.tapToNavigate,
              onChanged: (val) {
                _update(_current.copyWith(tapToNavigate: val));
              },
            ),
            if (_current.tapToNavigate)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Инвертировать зоны тапа'),
                subtitle: const Text('Поменять местами Следующая/Предыдущая'),
                value: _current.invertTap,
                onChanged: (val) {
                  _update(_current.copyWith(invertTap: val));
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Тап по центру открывает меню'),
              subtitle: const Text('Показывает или скрывает панели управления'),
              value: _current.tapCenterForMenu,
              onChanged: (val) {
                _update(_current.copyWith(tapCenterForMenu: val));
              },
            ),
            const SizedBox(height: 16),

            // Фон страницы
            const Text(
              'Цвет фона',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildThemeColorBtn(
                  title: 'AMOLED',
                  color: Colors.black,
                  theme: ColorTheme.pureBlack,
                ),
                const SizedBox(width: 12),
                _buildThemeColorBtn(
                  title: 'Тёмно-серый',
                  color: const Color(0xFF1E222B),
                  theme: ColorTheme.darkGrey,
                ),
                const SizedBox(width: 12),
                _buildThemeColorBtn(
                  title: 'Светлый',
                  color: const Color(0xFFF0F2F5),
                  theme: ColorTheme.light,
                  textColor: Colors.black,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Быстрый переход к странице
            const Text(
              'Перейти к странице',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jumpController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '1 - ${widget.totalPages}',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixText: '/ ${widget.totalPages}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final p = int.tryParse(_jumpController.text);
                    if (p != null && p >= 1 && p <= widget.totalPages) {
                      widget.onPageJump(p - 1);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Перейти'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChoice({
    required String label,
    required IconData icon,
    required ReaderMode mode,
  }) {
    final isSelected = _current.mode == mode;
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (selected) {
        if (selected) {
          _update(_current.copyWith(mode: mode));
        }
      },
    );
  }

  Widget _buildFitOption({
    required String label,
    required ImageFit fit,
    required IconData icon,
  }) {
    final isSelected = _current.imageFit == fit;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => _update(_current.copyWith(imageFit: fit)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primary : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? primary.withOpacity(0.12) : Colors.transparent,
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? primary : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeColorBtn({
    required String title,
    required Color color,
    required ColorTheme theme,
    Color textColor = Colors.white,
  }) {
    final isSelected = _current.colorTheme == theme;
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: () => _update(_current.copyWith(colorTheme: theme)),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.grey.withOpacity(0.3),
              width: isSelected ? 2.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
