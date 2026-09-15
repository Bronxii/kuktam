import 'package:flutter/material.dart';

// Stable feature IDs allow later presentation metadata without an entitlement
// system. No tier information is currently stored or displayed.
const _pages = [
  (
    id: 'recipes',
    icon: Icons.menu_book_outlined,
    title: 'Tartsd egy helyen a saját receptjeidet.',
    body:
        'Hozz létre, szerkessz és keress a receptjeid között egyszerűen. A hozzávalókat, fűszereket és az elkészítés menetét külön kezelheted, így minden recept átlátható és könnyen visszakereshető.',
  ),
  (
    id: 'shopping',
    icon: Icons.shopping_cart_outlined,
    title: 'A szükséges hozzávalók mindig kéznél vannak.',
    body:
        'Adj tételeket kézzel a bevásárlólistához, vagy küldd át őket közvetlenül egy receptből. Az azonos tételeket a Kuktám összevonja, a megvett dolgokat pedig kipipálhatod, így a lista mindig rendezett marad.',
  ),
  (
    id: 'text_import',
    icon: Icons.content_paste_outlined,
    title: 'Másold be, a Kuktám pedig segít feldolgozni.',
    body:
        'Illessz be receptet vagy bevásárlólistát egyszerű szövegként, és az alkalmazás megpróbálja felismerni a neveket, mennyiségeket és mértékegységeket. Mentés előtt mindent átnézhetsz és javíthatsz, így mindig te döntöd el, mi kerül be.',
  ),
  (
    id: 'scaling',
    icon: Icons.calculate_outlined,
    title: 'Igazítsd a receptet ahhoz, amennyire szükséged van.',
    body:
        'Egy szorzóval vagy egy kiválasztott hozzávaló kívánt mennyisége alapján az összes hozzávalót automatikusan újraszámolhatod. Az eredeti recept változatlan marad, az átszámított mennyiségeket pedig akár rögtön a bevásárlólistához is adhatod.',
  ),
  (
    id: 'what_to_cook',
    icon: Icons.lightbulb_outline,
    title: 'Találd meg, mit tudsz elkészíteni abból, ami otthon van.',
    body:
        'Add meg a nálad lévő hozzávalókat, a Kuktám pedig megkeresi azokat a recepteket, amelyekhez minden szükséges alapanyag rendelkezésre áll. Így könnyebb eldönteni, mi legyen a következő étel.',
  ),
];

class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({
    super.key,
    required this.onFinish,
    this.saving = false,
    this.error,
  });

  final VoidCallback onFinish;
  final bool saving;
  final String? error;

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (widget.saving) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) _go(_page - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Kuktám', style: theme.textTheme.titleLarge),
                    ),
                    TextButton(
                      onPressed: widget.saving ? null : widget.onFinish,
                      child: const Text('Kihagyás'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  physics: widget.saving
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: _pages.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SingleChildScrollView(
                          key: PageStorageKey(page.id),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    page.icon,
                                    size: 64,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                header: true,
                                child: Text(
                                  page.title,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                page.body,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.error != null) ...[
                      Text(
                        widget.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.saving) const LinearProgressIndicator(),
                    Semantics(
                      liveRegion: true,
                      label: '${_page + 1}. oldal az ${_pages.length}-ből',
                      child: ExcludeSemantics(
                        child: Text('${_page + 1} / ${_pages.length}'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (_page > 0)
                          TextButton(
                            onPressed: widget.saving
                                ? null
                                : () => _go(_page - 1),
                            child: const Text('Vissza'),
                          ),
                        FilledButton(
                          onPressed: widget.saving
                              ? null
                              : _page == _pages.length - 1
                              ? widget.onFinish
                              : () => _go(_page + 1),
                          child: Text(
                            _page == _pages.length - 1
                                ? 'Kezdjük'
                                : 'Következő',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
