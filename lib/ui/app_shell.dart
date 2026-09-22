import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/backend.dart';
import '../data/models.dart';
import '../data/site_controller.dart';
import '../pages/cameras_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/equipment_page.dart';
import '../pages/support_page.dart';
import '../pages/maintenance_page.dart';
import 'data_scope.dart';
import 'notifications_panel.dart';
import '../pages/settings_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.onLogout, this.userEmail});

  /// Affiché quand l'authentification est active (backend configuré).
  final VoidCallback? onLogout;

  /// Email du compte connecté (affiché dans le menu compte du header).
  final String? userEmail;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<SupportPageState> _supportKey = GlobalKey<SupportPageState>();

  late final SiteController _data;

  static const _pagesLabels = [
    'Accueil',
    'Caméras',
    'Équipements',
    'Support',
    'Entretien',
  ];
  static const _pagesIcons = [
    Icons.space_dashboard_outlined,
    Icons.videocam_outlined,
    Icons.inventory_2_outlined,
    Icons.support_agent_outlined,
    Icons.build_circle_outlined,
  ];

  @override
  void initState() {
    super.initState();
    // Mode réel uniquement en production — AuthGate garantit un backend
    // configuré avant d'afficher le shell. En TEST, [AppShellForTest]
    // fournit des données locales (Supabase non initialisable en test).
    if (AppConfig.isBackendConfigured && backend != null) {
      _data = SiteController.live(backend!);
      _data.load();
    } else {
      _data = SiteController.demoForTest();
    }
    _data.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _data.removeListener(_onDataChanged);
    _data.dispose();
    super.dispose();
  }

  /// Pages du shell — GETTER volontairement recalculé à chaque build :
  /// des widgets identiques (liste `late final` en cache) seraient SKIPPÉS
  /// par Flutter lors d'un changement de thème → pages figées sur l'ancienne
  /// palette (mélange noir/blanc au retour de navigation). Recréer les
  /// instances préserve les State (l'élément est mis à jour, pas recréé).
  /// Pages du shell — GETTER recalculé à chaque build ET SANS `const` :
  /// un widget const est canonisé (même instance à chaque build) → Flutter
  /// SAUTE son rebuild → page figée sur l'ancienne palette au changement de
  /// thème (mélange noir/blanc). Les State sont préservés : même type +
  /// même clé → l'élément est mis à jour, pas recréé.
  List<Widget> get _pages => [
    DashboardPage(
      onOpenEquipment: () => _select(2),
      onOpenSupport: () => _select(3),
      onOpenMaintenance: () => _select(4),
      onReportIncident: _openIncidentForm,
    ),
    CamerasPage(),
    EquipmentPage(),
    SupportPage(key: _supportKey),
    MaintenancePage(),
  ];

  void _select(int i) {
    setState(() => _index = i);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _openIncidentForm() {
    _select(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _supportKey.currentState?.openIncidentForm();
    });
  }

  Future<void> _openNotifications() => showNotificationsPanel(context, _data);

  /// Ouvre la page Paramètres (thème, réseau, notifications, compte).
  /// ⚠️ La route poussée vit au-dessus du DataScope (Navigator) : on
  /// l'enveloppe pour que `DataScope.of(context)` y soit résoluble —
  /// sinon crash de build → écran blanc en release.
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DataScope(
          controller: _data,
          child: SettingsPage(
            userEmail: widget.userEmail,
            onLogout: widget.onLogout,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showSidebar = width >= 1100;
    final showTopNav = width >= 900;

    return DataScope(
      controller: _data,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.background,
        drawer: showSidebar
            ? null
            : Drawer(
                backgroundColor: AppColors.sidebar,
                child: SafeArea(
                  child: _SidebarContent(
                    selectedIndex: _index,
                    onSelect: _select,
                    onReportIncident: _openIncidentForm,
                    onSettings: _openSettings,
                    onLogout: widget.onLogout,
                  ),
                ),
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                showMenu: !showSidebar,
                showNav: showTopNav,
                selectedIndex: _index,
                onSelect: _select,
                onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                onSettings: _openSettings,
                onNotifications: _openNotifications,
                unreadCount: _data.unreadCount,
                onLogout: widget.onLogout,
                userEmail: widget.userEmail,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showSidebar)
                      _SidebarContent(
                        selectedIndex: _index,
                        onSelect: _select,
                        onReportIncident: _openIncidentForm,
                        onSettings: _openSettings,
                        onLogout: widget.onLogout,
                      ),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Zone de contenu : états chargement / erreur / aucun site, puis les pages.
  Widget _buildBody() {
    if (_data.isLive && _data.loading && _data.equipment.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_data.error != null) {
      return _MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Connexion au serveur impossible',
        message: _data.error!,
        actionLabel: 'Réessayer',
        onAction: () => _data.load(),
      );
    }
    if (_data.noSite) {
      return _CreateSiteView(onCreated: () {});
    }
    return IndexedStack(index: _index, children: _pages);
  }
}

/// Auto-service d'inscription : un compte tout juste créé n'a pas encore
/// d'installation — le client crée la sienne ici (il en devient
/// propriétaire, RLS `sites_insert` avec `owner_id = auth.uid()`).
class _CreateSiteView extends StatefulWidget {
  const _CreateSiteView({required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<_CreateSiteView> createState() => _CreateSiteViewState();
}

class _CreateSiteViewState extends State<_CreateSiteView> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final data = DataScope.of(context);
    setState(() => _busy = true);
    final error = await data.createSite(
      name: _name.text,
      address: _address.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.home_work_outlined,
                  size: 30,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Créez votre installation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bienvenue ! Nommez votre installation (maison, boutique, '
                'entrepôt…) pour commencer à y ajouter vos caméras.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nom de l\'installation (ex : Boutique Angré)',
                  labelStyle: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: TextStyle(color: AppColors.onSurface),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Adresse (facultatif)',
                  labelStyle: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: TextStyle(color: AppColors.onSurface),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: monoStyle(11, height: 1.4, color: AppColors.error),
                ),
              ],
              const SizedBox(height: 20),
              _busy
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : PrimaryButton(
                      label: 'Créer mon installation',
                      icon: Icons.home_work_outlined,
                      onTap: _submit,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              PrimaryButton(
                label: actionLabel!,
                icon: Icons.refresh,
                onTap: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.showMenu,
    required this.showNav,
    required this.selectedIndex,
    required this.onSelect,
    required this.onMenu,
    required this.onSettings,
    required this.onNotifications,
    required this.unreadCount,
    this.onLogout,
    this.userEmail,
  });

  final bool showMenu;
  final bool showNav;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final VoidCallback onNotifications;
  final int unreadCount;

  /// Déconnexion du compte (client ou technicien) — masqué en mode démo.
  final VoidCallback? onLogout;

  /// Email du compte connecté, affiché dans le menu compte.
  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (showMenu)
            IconButton(icon: const Icon(Icons.menu), onPressed: onMenu),
          _logo(),
          if (showNav)
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var i = 0;
                      i < AppShellState._pagesLabels.length;
                      i++
                    ) ...[
                      _HeaderNav(
                        label: AppShellState._pagesLabels[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelect(i),
                      ),
                      const SizedBox(width: 28),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          _bellButton(),
          const SizedBox(width: 8),
          CircleIconButton(
            icon: Icons.settings_outlined,
            size: 38,
            iconSize: 18,
            onTap: onSettings,
          ),
          if (onLogout != null) ...[
            const SizedBox(width: 8),
            _accountButton(context),
          ],
        ],
      ),
    );
  }

  /// Bouton compte (client / technicien) avec menu de déconnexion.
  Widget _accountButton(BuildContext context) {
    final data = DataScope.of(context);
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 260),
      color: AppColors.card,
      itemBuilder: (menuContext) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.roleLabel,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail ?? 'Compte connecté',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(10.5, color: AppColors.onSurfaceFaint),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.logout_outlined, size: 18, color: AppColors.error),
              const SizedBox(width: 10),
              Text(
                'Se déconnecter',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value != 'logout') return;
        final confirmed = await _confirmSignOut(context);
        if (confirmed && onLogout != null) onLogout!();
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.card,
          border: Border.all(color: AppColors.outline),
        ),
        child: Icon(
          Icons.person_outline,
          size: 18,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<bool> _confirmSignOut(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Se déconnecter ?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        content: Text(
          'Vous revenez à l\'écran de connexion et pourrez vous reconnecter '
          'avec vos identifiants client ou technicien.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          PrimaryButton(
            label: 'Se déconnecter',
            icon: Icons.logout_outlined,
            color: AppColors.error,
            height: 42,
            uppercase: false,
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _logo() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'Logo/securcam_logo.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'EYESAFE',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bellButton() {
    final count = unreadCount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onNotifications,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.card,
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.card, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.card,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderNav extends StatefulWidget {
  const _HeaderNav({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HeaderNav> createState() => _HeaderNavState();
}

class _HeaderNavState extends State<_HeaderNav> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              child: Text(widget.label),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2.5,
              width: widget.selected ? 24 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.selectedIndex,
    required this.onSelect,
    required this.onReportIncident,
    required this.onSettings,
    this.onLogout,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onReportIncident;
  final VoidCallback onSettings;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'Logo/securcam_logo.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'EYESAFE',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < AppShellState._pagesLabels.length; i++)
            _SideItem(
              icon: AppShellState._pagesIcons[i],
              label: AppShellState._pagesLabels[i],
              selected: selectedIndex == i,
              onTap: () => onSelect(i),
            ),
          const SizedBox(height: 12),
          _incidentButton(),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 8),
          _SiteSelector(
            siteLabel: data.contract?.siteLabel ?? 'Mon installation',
            roleLabel: data.roleLabel,
            sites: data.sites,
            activeSiteId: data.activeSiteId,
            onSwitch: data.switchSite,
          ),
          const SizedBox(height: 8),
          _SideItem(
            icon: Icons.settings_outlined,
            label: 'Paramètres',
            selected: false,
            onTap: onSettings,
          ),
          if (onLogout != null) ...[
            const SizedBox(height: 4),
            _SideItem(
              icon: Icons.logout_outlined,
              label: 'Déconnexion',
              selected: false,
              onTap: () => onLogout?.call(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _incidentButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onReportIncident,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.report_problem_outlined,
                color: AppColors.card,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Signaler un incident',
                style: monoStyle(
                  11.5,
                  weight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Identité du site actif dans la barre latérale.
/// Avec plusieurs sites, un appui ouvre le sélecteur.
class _SiteSelector extends StatelessWidget {
  const _SiteSelector({
    required this.siteLabel,
    required this.roleLabel,
    required this.sites,
    required this.activeSiteId,
    required this.onSwitch,
  });

  final String siteLabel;
  final String roleLabel;
  final List<SiteSummary> sites;
  final String? activeSiteId;
  final ValueChanged<String> onSwitch;

  bool get _hasChoice => sites.length > 1;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _hasChoice ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: _hasChoice ? () => _openSelector(context) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hasChoice ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hasChoice ? AppColors.outlineVariant : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: AppColors.card,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(12, weight: FontWeight.w700),
                    ),
                    Text(
                      _hasChoice
                          ? 'Installation · $roleLabel · ${sites.length} sites ▾'
                          : 'Installation · $roleLabel',
                      style: monoStyle(10, color: AppColors.onSurfaceVariant),
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

  void _openSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Changer d'installation",
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Vos sites accessibles',
                style: monoStyle(10.5, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              for (final site in sites) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _SiteTile(
                    site: site,
                    active: site.id == activeSiteId,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onSwitch(site.id);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({required this.site, required this.active, this.onTap});

  final SiteSummary site;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? AppColors.primaryContainer : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: active ? Colors.white : AppColors.surface,
                ),
                child: Icon(
                  site.isOwner
                      ? Icons.storefront_outlined
                      : Icons.engineering_outlined,
                  size: 20,
                  color: active
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (site.plan?.isNotEmpty == true)
                      Text(
                        site.plan!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(10, color: AppColors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (active)
                Icon(Icons.check_circle, size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primaryContainer
                  : _hover
                  ? AppColors.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: active
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
