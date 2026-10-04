import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/potia_logo.dart';

enum AuthTab { login, register }

class AuthView extends StatefulWidget {
  const AuthView({super.key, this.initialTab = AuthTab.login});

  final AuthTab initialTab;

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.index);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _goToChat() {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.chat, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Voltar',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : const SizedBox(height: 48),
            ),
            const PotiaLogo(size: 76),
            const SizedBox(height: 16),
            Text('Bem-vindo(a) à PotIA', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Entre para começar a cozinhar com IA',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.creamDeep),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                tabs: const [Tab(text: 'Entrar'), Tab(text: 'Cadastrar')],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _LoginForm(onSuccess: _goToChat),
                  _RegisterForm(onSuccess: _goToChat),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(email: _emailController.text, password: _passwordController.text);
    if (!mounted) return;
    if (success) {
      widget.onSuccess();
    } else {
      showAppSnackBar(context, auth.errorMessage ?? 'Não foi possível entrar.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<AuthProvider, bool>((auth) => auth.isLoading);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: AppTheme.inputDecoration(label: 'E-mail', icon: Icons.alternate_email_rounded),
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: AppTheme.inputDecoration(
                  label: 'Senha',
                  icon: Icons.lock_outline_rounded,
                  suffix: _VisibilityToggle(
                    obscured: _obscurePassword,
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: Validators.loginPassword,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading ? const _ButtonSpinner() : const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      showAppSnackBar(context, 'Conta criada! Bora cozinhar? 🍳');
      widget.onSuccess();
    } else {
      showAppSnackBar(context, auth.errorMessage ?? 'Não foi possível criar a conta.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<AuthProvider, bool>((auth) => auth.isLoading);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: AppTheme.inputDecoration(label: 'Nome', icon: Icons.person_outline_rounded),
                validator: Validators.name,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: AppTheme.inputDecoration(label: 'E-mail', icon: Icons.alternate_email_rounded),
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: AppTheme.inputDecoration(
                  label: 'Senha',
                  hint: 'Mínimo 8 caracteres, com letras e números',
                  icon: Icons.lock_outline_rounded,
                  suffix: _VisibilityToggle(
                    obscured: _obscurePassword,
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: Validators.newPassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: AppTheme.inputDecoration(label: 'Confirmar senha', icon: Icons.lock_outline_rounded),
                validator: Validators.confirmPassword(() => _passwordController.text),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading ? const _ButtonSpinner() : const Text('Criar conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: obscured ? 'Mostrar senha' : 'Esconder senha',
        icon: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: onPressed,
      );
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
      );
}
