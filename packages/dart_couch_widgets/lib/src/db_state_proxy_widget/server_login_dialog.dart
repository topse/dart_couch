import 'package:dart_couch/dart_couch.dart';
import 'package:flutter/material.dart';

/// A dialog widget that prompts the user for a server URL, username and password.
class ServerLoginDialog extends StatefulWidget {
  final LoginCredentials? initialCredentials;
  final String? errorMessage;
  final void Function(LoginCredentials)? onLogin;
  final bool isSaveCredentialsAvailable;

  const ServerLoginDialog({
    super.key,
    this.initialCredentials,
    this.errorMessage,
    this.onLogin,
    required this.isSaveCredentialsAvailable,
  });

  @override
  State<ServerLoginDialog> createState() => _ServerLoginDialogState();
}

class _ServerLoginDialogState extends State<ServerLoginDialog> {
  late bool _storeCredentials;
  String _selectedScheme = 'https';
  bool _obscure = true;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    String url = widget.initialCredentials?.url ?? '';
    if (url.startsWith('http://')) {
      _selectedScheme = 'http';
      url = url.substring(7);
    } else if (url.startsWith('https://')) {
      _selectedScheme = 'https';
      url = url.substring(8);
    }
    _urlController = TextEditingController(text: url);
    _usernameController = TextEditingController(
      text: widget.initialCredentials?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.initialCredentials?.password ?? '',
    );
    _storeCredentials = widget.initialCredentials?.storeCredentials ?? false;
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      String url = _urlController.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = '$_selectedScheme://$url';
      }
      if (widget.onLogin != null) {
        widget.onLogin!(
          LoginCredentials(
            url: url,
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            storeCredentials:
                widget.isSaveCredentialsAvailable && _storeCredentials,
          ),
        );
      }
    }
  }

  // End of class
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Connect to Server',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.start,
                    ),
                    if (widget.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text(
                          widget.errorMessage!,
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _selectedScheme,
                          items: const [
                            DropdownMenuItem(
                              value: 'https',
                              child: Text('https'),
                            ),
                            DropdownMenuItem(
                              value: 'http',
                              child: Text('http'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedScheme = value);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              labelText: 'Server URL',
                              hintText: 'example.com',
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Please enter a server URL';
                              // No scheme check needed, handled by dropdown
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Please enter a username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if ((value ?? '').isEmpty) {
                          return 'Please enter a password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.isSaveCredentialsAvailable)
                          Checkbox(
                            value: _storeCredentials,
                            onChanged: (v) =>
                                setState(() => _storeCredentials = v ?? false),
                          ),
                        const Text('Store username and password'),
                        const Spacer(),
                        FilledButton(
                          onPressed: _submit,
                          child: const Text('Connect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
