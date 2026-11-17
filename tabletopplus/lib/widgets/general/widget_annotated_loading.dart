import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../providers/provider_auth.dart';
import '../../util/message_display/snackbar.dart';

class WidgetAnnotatedLoading extends ConsumerStatefulWidget {
  const WidgetAnnotatedLoading({
    super.key,
    this.height = 250,
    this.loadingText = '',
    this.timeOutEnabled = false,
    this.timeOutSecs = 15,
    this.timeOutTextPrefix = 'Loading',
    this.timeOutCountdownBeginsAtSecs = 5,
    this.timeOutSignsOut = false,
    this.timeOutCallback,
    this.quietTimeOut = false,
    this.loadingTexts,
  });

  final String loadingText;
  final double height;
  final bool timeOutEnabled;
  final int timeOutSecs;
  final String timeOutTextPrefix;
  final int timeOutCountdownBeginsAtSecs;
  final bool timeOutSignsOut;
  final bool quietTimeOut;
  final VoidCallback? timeOutCallback;
  final List<String>? loadingTexts;

  @override
  ConsumerState<WidgetAnnotatedLoading> createState() => _WidgetAnnotatedLoadingState();
}

class _WidgetAnnotatedLoadingState extends ConsumerState<WidgetAnnotatedLoading> {
  Timer? _timer;
  late int _remaining;
  int _displayIndex = 0;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant WidgetAnnotatedLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadingText != widget.loadingText ||
        oldWidget.timeOutEnabled != widget.timeOutEnabled ||
        oldWidget.timeOutSecs != widget.timeOutSecs) {
      _timer?.cancel();
      _startTimer();
    }
  }

  void _startTimer() {
    _remaining = widget.timeOutSecs;
    _timedOut = false;
    _displayIndex = 0;
    if (!widget.timeOutEnabled) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() { _remaining = 0; _timedOut = true; });
        if (widget.timeOutSignsOut) {
          Snackbar.show(
            SnackbarDisplayType.SB_ERROR,
            '${widget.timeOutTextPrefix} took too long. Signing out.',
            context,
          );
          await ref.read(providerAuth.notifier).clearAuthedUserDetailsAndSignout();
        } else {
          widget.timeOutCallback?.call();
          if (!widget.quietTimeOut && mounted) {
            Snackbar.show(
              SnackbarDisplayType.SB_ERROR,
              '${widget.timeOutTextPrefix} took too long. Please check your connection.',
              context,
            );
          }
        }
        return;
      }
      setState(() {
        _remaining -= 1;
        final texts = widget.loadingTexts;
        if (_remaining % 5 == 0 && texts != null && texts.isNotEmpty) {
          _displayIndex = (_displayIndex + 1) % texts.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = widget.loadingTexts;
    final display = texts != null && texts.isNotEmpty
        ? texts[_displayIndex % texts.length]
        : widget.loadingText;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(child: Lottie.asset('animations/loading_dots.json', height: widget.height)),
        if (display.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(display, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        ],
        if (widget.timeOutEnabled &&
            !_timedOut &&
            _remaining <= widget.timeOutCountdownBeginsAtSecs &&
            !widget.quietTimeOut)
          Text('Timing out in $_remaining seconds...',
              style: const TextStyle(fontStyle: FontStyle.italic)),
      ],
    );
  }
}
