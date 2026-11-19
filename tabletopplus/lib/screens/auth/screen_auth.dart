// -----------------------------------------------------------------------
// Filename: provider_auth.dart
// Original Author: Dan Grissom
// Creation Date: 5/22/2024
// Copyright: (c) 2024 CSC322
// Description: This file contains the screen for authenticating users
//              (login, account creation).

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Flutter external package imports
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:auto_route/auto_route.dart';
// import 'package:provider/provider.dart';

// App relative file imports
import '../../util/message_display/popup_dialogue.dart';
import '../../widgets/auth/widget_password_strength_indicator.dart';
import '../../providers/provider_user_profile.dart';
import '../../util/message_display/snackbar.dart';
import '../../util/logging/app_logger.dart';
import '../../providers/provider_auth.dart';
import '../../models/user_profile.dart';
import '../../theme/colors.dart';
// import '../../widgets/authentication/cloud_environment_banner_widget.dart';
// import '../../widgets/account/onboarding/onboarding_button.dart';
// import '../../providers/device_preferences_provider.dart';
// import '../../util/message_display/popup_dialogue.dart';
// import '../../providers/user_profile_provider.dart';
// import '../../util/message_display/snackbar.dart';
// import '../../constants/app/testing_keys.dart';
// import '../../util/print/print.dart';
// import '../../theme/colors.dart';

//////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the
// state object.
//////////////////////////////////////////////////////////////////
class ScreenAuth extends ConsumerStatefulWidget {
  static const routeName = '/auth';

  const ScreenAuth({super.key});

  @override
  ConsumerState<ScreenAuth> createState() => _ScreenAuthState();
}

//////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////
class _ScreenAuthState extends ConsumerState<ScreenAuth> {
  // The "instance variables" managed in this state
  bool _signInMode = true;
  bool _passwordVisible = false;
  var _isInit = true;
  late ProviderUserProfile _providerUserProfile;
  late ProviderAuth _providerAuth;
  String _strengthText = "";
  Color _strengthColor = CustomColors.statusWarning;
  double _passwordStrength = 0;

  // Finals used in this widget
  final _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  ////////////////////////////////////////////////////////////////
  // Runs the following code once upon initialization
  ////////////////////////////////////////////////////////////////
  @override
  void didChangeDependencies() {
    // If first time running this code, update provider settings
    if (_isInit) {
      _init();

      // First-time initialization complete.
      _isInit = false;
    }
    super.didChangeDependencies();
  }

  ////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////
  /// Helper Methods (for state object)
  ////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////

  ////////////////////////////////////////////////////////////////
  // Gets the current state of the providers for consumption on
  // this page
  ////////////////////////////////////////////////////////////////
  _init() async {
    _providerUserProfile = ref.read(providerUserProfile.notifier);
    _providerAuth = ref.read(providerAuth.notifier);
  }

  @override
  void initState() {
    super.initState();
    _passwordVisible = false;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  ////////////////////////////////////////////////////////////////
  // Attempts to either login to existing account or signup for
  // new account.
  ////////////////////////////////////////////////////////////////
  void _submitAuthForm(String email, String password, bool isLogin, BuildContext ctx) async {
    try {
      // Update screen to indicate loading spinner
      setState(() {});

      // If in "login mode", attempt to login with email/password...
      if (isLogin) {
        // Attempt login
        String errorMessage = (await _providerAuth.signinWithPassword(email, password)).trim();

        // If there was an error, display it...otherwise load the profile
        if (errorMessage.isNotEmpty) {
          if (mounted) {
            Snackbar.show(SnackbarDisplayType.SB_ERROR, errorMessage, context);
            setState(() {});
          }
        } else {
          await _providerAuth.loadAuthedUserDetailsUponSignin();
        }

        // }
      } else {
        // ...otherwise, attempt to create a new account
        // Attempt to create a new account
        await _auth.createUserWithEmailAndPassword(email: email, password: password);
        final user = _auth.currentUser;

        // Send verification e-mail and create initial user profile
        try {
          if (ENFORCE_EMAIL_VERIFICATION) {
            await FirebaseAuth.instance.currentUser?.sendEmailVerification();
          }
          _providerUserProfile.email = user?.email ?? email;
          _providerUserProfile.accountCreationStep = AccountCreationStep.ACC_STEP_ONBOARDING_PROFILE_CONTACT_INFO;
          final saved = await _providerUserProfile.writeUserProfileToDb();
          if (!saved && mounted) {
            Snackbar.show(SnackbarDisplayType.SB_WARNING,
                'Account created, but profile could not be saved. Retry after verification.', context);
          }
          _providerAuth.isSigningIn = false;
        } catch (e) {
          AppLogger.warning("Issue with sending email verification or writing to user profile.  email: $e");
        }

        // ...and send verification email
        if (user != null && !user.emailVerified) {
          // ...display a reminder; the verification e-mail was already sent above.
          // ...and display to user as "Snack bar" pop-up at bottom of screen
          if (mounted) {
            Snackbar.show(SnackbarDisplayType.SB_INFO, 'Check ${user.email} for verification link.', context);
          }
        }
      }
    } on FirebaseAuthException catch (err) {
      // If error, dis-engage loading screen and display to user
      if (!mounted) return;
      setState(() {});

      // If error occurs, gather error message...
      var message = 'An error occurred, please check your credentials!';
      if (err.message != null) message = err.message!;
      if (mounted) {
        Snackbar.show(SnackbarDisplayType.SB_ERROR, message, ctx);
      }
    }
  }

  ////////////////////////////////////////////////////////////////
  // Does basic validation and attempts to authenticate using the
  // method called in from the parent screen/widget.
  ////////////////////////////////////////////////////////////////
  void _trySubmit() {
    // Unfocus from any controls that may have focus to disengage the keyboard
    FocusScope.of(context).unfocus();

    // If the form validates, save the data and then execute the callback function,
    // which attempts to either login to existing account or signup for new account.
    final isValid = _formKey.currentState!.validate() &&
        (_signInMode || _passwordStrength >= .6);
    if (isValid) {
      _formKey.currentState!.save();
      _submitAuthForm(_emailController.text.trim(), _passwordController.text.trim(), _signInMode, context);
    } else if (!_signInMode && _passwordStrength < .6) {
      Snackbar.show(SnackbarDisplayType.SB_ERROR, "Please improve your password strength.", context);
    }
  }

  /* ---------------------------- validatePassword ---------------------------- */
  /// Does a check on the password inputted in the Password form.
  /// [value] is the value inputted by the user.
  /// Returns String if there was an error. Otherwise returns null.
  /// For this form a valid password must do all of the following:
  /// - Be 6 characters in length
  /// - Contain 1 letter
  /// - Contain 1 digit
  /// - Contain 1 symbol
  String? validatePasssword(String? value) {
    /// The password response message. Error messages are added to the end of it.
    String passwordResponse = "Password must have: ";

    /// Has the inputted password tripped an invalidation flag?
    bool invalidPassword = false;

    /// How many invalidation flags have been tripped?
    int errorCount = 0;

    /// Check if there was a password that was entered.
    if (value == null || value.isEmpty) {
      return 'Enter a password.';

      /// Validate the password
    } else {
      /// Make sure the password is at least 6 characters
      if (value.length < 6) {
        passwordResponse += "6 characters";
        invalidPassword = true;
        errorCount += 1;
      }

      /// Make sure the password contains a letter.
      if (!(RegExp(r"(?=.*[a-z])").hasMatch(value) || RegExp(r"(?=.*[A-Z])").hasMatch(value))) {
        if (invalidPassword) {
          passwordResponse += ", letter";
        } else {
          passwordResponse += "letter";
          invalidPassword = true;
        }
        errorCount += 1;
      }

      /// Make sure the password contains a number.
      if (!(RegExp(r"(?=.*\d)").hasMatch(value))) {
        if (invalidPassword) {
          passwordResponse += ", digit";
        } else {
          passwordResponse += "digit";
          invalidPassword = true;
        }
        errorCount += 1;
      }

      /// Make sure the password contains a special character.
      if (!(RegExp(r"(?=.*\W)").hasMatch(value))) {
        if (invalidPassword) {
          passwordResponse += ", symbol";
        } else {
          passwordResponse += "symbol";
          invalidPassword = true;
        }
        errorCount += 1;
      }

      /// Was the password marked as invalid?
      if (invalidPassword) {
        /// Punctuate the end of the error with a period.
        passwordResponse += ".";

        /// The comma checks to see if there was enough errors to add a comma
        /// to the response. (This would be 3)
        if (passwordResponse.contains(", ")) {
          /// Grab the index of the last occuring comma
          int lastIndex = passwordResponse.lastIndexOf(", ");

          /// Replace it with either "and" or ", and" for correct grammar
          String endingPhrase = (errorCount > 2) ? ", and" : " and";
          passwordResponse =
              passwordResponse.substring(0, lastIndex) +
              endingPhrase +
              passwordResponse.substring(lastIndex + 1, passwordResponse.length);
        }

        return passwordResponse;
      }
      return null;
    }
  }

  /* ------------------------- validateConfirmPassword ------------------------ */
  /// Ensures that the passwords put into confirm password and password fields match.
  /// [value] is the value inputted by the user.
  /// Returns String if there was an error. Otherwise returns null.
  String? validateConfirmPassword(String? value) {
    if (_signInMode) {
      return null;
    }

    /// Check if there was a password typed into the field
    if ((value == null || value.isEmpty)) {
      return 'Confirm your password.';
    }
    /// Check to make sure the passwords match
    else {
      if (_confirmPasswordController.text != _passwordController.text) {
        return "Passwords do not match.";
      }
      return null;
    }
  }

  Widget animatedWidget({required Widget child, double? height}) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.center, children: [child]),
    );
  }

  void showPopup() {
    PopupDialogue.showTextField(
      "Reset Password",
      "Email",
      context,
      (email) async {
        bool success = await resetPassword(email);
        if (success && mounted) {
          Navigator.of(context).pop();
          AppLogger.print("Reset password email sent to $email");
        }
      },
      buttonText: "Reset Password",
      defaultValue: _emailController.text,
    );
  }

  Future<bool> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('If this account exists, a reset email was sent. Check your spam folder.')),
        );
      }
      return true;
    } on FirebaseAuthException catch (error) {
      AppLogger.error('Failed to send password reset email: $error');
      if (mounted) {
        Snackbar.show(SnackbarDisplayType.SB_ERROR, 'Could not send reset email. Check the address.', context);
      }
      return false;
    } catch (error) {
      AppLogger.error('Unexpected password reset error: $error');
      if (mounted) Snackbar.show(SnackbarDisplayType.SB_ERROR, 'Unable to reset password right now.', context);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the existing authentication and account-creation logic intact.
    ref.watch(providerUserProfile);
    const darkBrown = Color(0xFF55412D);
    const warmBrown = Color(0xFF8A6A43);
    const warmYellow = Color(0xFFF1CD58);
    const cream = Color(0xFFFFFAF1);
    const border = Color(0xFFEADFCC);

    InputDecoration fieldStyle(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: warmBrown),
          prefixIcon: Icon(icon, color: warmBrown, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: warmBrown, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The user's tabletop icon, without the original
                          // transparent padding surrounding it.
                          Image.asset(
                            'images/tabletopplus_mark.png',
                            height: 112,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.casino_outlined,
                              size: 90,
                              color: warmBrown,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'TableTopPlus',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: darkBrown,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Your adventures, all in one place.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: warmBrown),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                            decoration: BoxDecoration(
                              color: cream,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: border),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x146D5133),
                                  blurRadius: 24,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _signInMode ? 'Welcome back' : 'Begin your adventure',
                                  style: const TextStyle(
                                    fontSize: 23,
                                    color: darkBrown,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _signInMode
                                      ? 'Sign in to return to your table.'
                                      : 'Create an account to share your stories.',
                                  style: const TextStyle(color: warmBrown, fontSize: 13),
                                ),
                                const SizedBox(height: 22),
                                TextFormField(
                                  controller: _emailController,
                                  autofillHints: const [AutofillHints.username],
                                  autocorrect: false,
                                  textCapitalization: TextCapitalization.none,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: fieldStyle('Email address', Icons.mail_outline),
                                  validator: (value) {
                                    if (value == null ||
                                        value.trim().isEmpty ||
                                        !value.contains('@') ||
                                        !value.contains('.')) {
                                      return 'Please enter a valid email address.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _passwordController,
                                  autofillHints: const [AutofillHints.password],
                                  enableInteractiveSelection: true,
                                  obscureText: !_passwordVisible,
                                  decoration: fieldStyle('Password', Icons.lock_outline).copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                                      icon: Icon(
                                        _passwordVisible
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: warmBrown,
                                      ),
                                      onPressed: () =>
                                          setState(() => _passwordVisible = !_passwordVisible),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return 'Enter a password.';
                                    return _signInMode ? null : validatePasssword(value);
                                  },
                                  onChanged: (_) {
                                    _passwordStrength = getPasswordStrength(_passwordController.text);
                                    _strengthText = getPasswordStrengthText(_passwordStrength);
                                    _strengthColor = getPasswordStrengthColor(_passwordStrength);
                                    setState(() {});
                                  },
                                  onFieldSubmitted: (_) {
                                    if (_signInMode) _trySubmit();
                                  },
                                ),
                                if (_signInMode)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      style: TextButton.styleFrom(foregroundColor: warmBrown),
                                      onPressed: showPopup,
                                      child: const Text('Forgot password?'),
                                    ),
                                  ),
                                if (!_signInMode) ...[
                                  if (_passwordController.text.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    WidgetPasswordStrengthIndicator(
                                      passwordStrength: _passwordStrength,
                                      passwordText: _strengthText,
                                      passwordColor: _strengthColor,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    obscureText: !_passwordVisible,
                                    autocorrect: false,
                                    textCapitalization: TextCapitalization.none,
                                    enableSuggestions: false,
                                    decoration: fieldStyle(
                                      'Confirm password',
                                      Icons.verified_user_outlined,
                                    ),
                                    validator: validateConfirmPassword,
                                    onFieldSubmitted: (_) => _trySubmit(),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: darkBrown,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: _trySubmit,
                                    child: Text(
                                      _signInMode ? 'Sign in' : 'Create account',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  style: TextButton.styleFrom(foregroundColor: darkBrown),
                                  onPressed: () => setState(() => _signInMode = !_signInMode),
                                  child: Text(
                                    _signInMode
                                        ? 'New to the table? Create an account'
                                        : 'Already have an account? Sign in',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_stories_outlined, size: 17, color: warmBrown),
                              SizedBox(width: 9),
                              Text(
                                'Gather • Create • Explore',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: warmBrown,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 42,
                            height: 3,
                            decoration: BoxDecoration(
                              color: warmYellow,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
