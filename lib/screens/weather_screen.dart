import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/friendly_error.dart';
import '../core/weather_service.dart';
import '../widgets/weather_app_bar_title.dart';

/// Full weather page: current conditions, 24 hour forecast and a week ahead.
///
/// Data comes from the 中央氣象署 open data platform, the same source as the app
/// bar chip, through the shared [WeatherService] so opening this page right
/// after the chip refreshed reuses that reading instead of making another
/// request.
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({
    this.latitude,
    this.longitude,
    this.serviceOverride,
    this.locationOverride,
    super.key,
  });

  /// Position the caller already resolved, so the page can skip a second
  /// location lookup. Both must be provided together.
  final double? latitude;
  final double? longitude;

  @visibleForTesting
  final WeatherService? serviceOverride;

  @visibleForTesting
  final PassiveLocationResolver? locationOverride;

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  WeatherForecast? _forecast;
  String? _error;
  bool _loading = true;
  bool _locationUnavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  WeatherService get _service => widget.serviceOverride ?? WeatherService.shared;

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _locationUnavailable = false;
      });
    }

    double? latitude = widget.latitude;
    double? longitude = widget.longitude;
    if (latitude == null || longitude == null) {
      final resolve = widget.locationOverride ?? resolvePassivePosition;
      final Position? position = await resolve();
      latitude = position?.latitude;
      longitude = position?.longitude;
    }

    if (!mounted) {
      return;
    }
    if (latitude == null || longitude == null) {
      setState(() {
        _loading = false;
        _locationUnavailable = true;
      });
      return;
    }

    try {
      final forecast = await _service.fetchForecast(
        latitude: latitude,
        longitude: longitude,
        force: force,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _forecast = forecast;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        // Strips exception prefixes and translates network/timeout errors,
        // like every other screen in the app.
        _error = friendlyErrorMessage(error, fallback: _genericWeatherError);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final forecast = _forecast;
    return Scaffold(
      appBar: AppBar(
        title: const Text('天氣'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新整理',
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (forecast != null) ..._content(context, forecast),
            if (forecast == null && _loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 96),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (forecast == null && !_loading) _placeholder(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, WeatherForecast forecast) {
    return [
      _currentCard(context, forecast),
      if (forecast.hourly.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, '逐時'),
        const SizedBox(height: 8),
        _hourlyStrip(context, forecast.hourly),
      ],
      if (forecast.daily.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, '一週'),
        const SizedBox(height: 8),
        _weeklyList(context, forecast.daily),
      ],
      if (forecast.sunrise != null || forecast.sunset != null) ...[
        const SizedBox(height: 24),
        _sunRow(context, forecast),
      ],
      const SizedBox(height: 24),
      _footer(context, forecast),
      // Errors while a forecast is already on screen keep the stale data.
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  Widget _currentCard(BuildContext context, WeatherForecast forecast) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = forecast.current;
    final today = forecast.daily.isNotEmpty ? forecast.daily.first : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Icon(
              weatherConditionIcon(current.condition),
              size: 72,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '${current.displayTemperature}°C',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              weatherConditionLabel(current.condition),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              forecast.locationLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (today != null) ...[
              const SizedBox(height: 4),
              Text(
                '最高 ${today.displayHigh}° · 最低 ${today.displayLow}°',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (forecast.apparentTemperatureC != null)
                  _metric(
                    context,
                    Icons.thermostat,
                    '體感',
                    '${forecast.apparentTemperatureC!.round()}°',
                  ),
                if (forecast.relativeHumidity != null)
                  _metric(
                    context,
                    Icons.water_drop_outlined,
                    '濕度',
                    '${forecast.relativeHumidity}%',
                  ),
                if (forecast.windSpeedKph != null)
                  _metric(
                    context,
                    Icons.air,
                    '風速',
                    '${forecast.windSpeedKph!.round()} km/h',
                  ),
                if (today?.precipitationProbability != null)
                  _metric(
                    context,
                    Icons.umbrella_outlined,
                    '降雨',
                    '${today!.precipitationProbability}%',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _hourlyStrip(BuildContext context, List<WeatherHourly> hours) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (context, index) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final hour = hours[index];
          return SizedBox(
            width: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  index == 0 ? '現在' : '${hour.time.hour}時',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Icon(
                  weatherConditionIcon(hour.condition),
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  '${hour.displayTemperature}°',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // A blank line keeps every cell the same height.
                  hour.precipitationProbability == null
                      ? ''
                      : '${hour.precipitationProbability}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _weeklyList(BuildContext context, List<WeatherDaily> days) {
    var weekLow = days.first.lowC;
    var weekHigh = days.first.highC;
    for (final day in days) {
      weekLow = math.min(weekLow, day.lowC);
      weekHigh = math.max(weekHigh, day.highC);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var index = 0; index < days.length; index++)
              _weeklyRow(context, days[index], index, weekLow, weekHigh),
          ],
        ),
      ),
    );
  }

  Widget _weeklyRow(
    BuildContext context,
    WeatherDaily day,
    int index,
    double weekLow,
    double weekHigh,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              dayLabel(day.date, index),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Icon(
            weatherConditionIcon(day.condition),
            size: 20,
            color: theme.colorScheme.primary,
          ),
          SizedBox(
            width: 44,
            child: Text(
              day.precipitationProbability == null
                  ? ''
                  : '${day.precipitationProbability}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text(
              '${day.displayLow}°',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _rangeBar(context, day, weekLow, weekHigh)),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '${day.displayHigh}°',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeBar(
    BuildContext context,
    WeatherDaily day,
    double weekLow,
    double weekHigh,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final span = weekHigh - weekLow;
    final start = span <= 0 ? 0.0 : (day.lowC - weekLow) / span;
    final end = span <= 0 ? 1.0 : (day.highC - weekLow) / span;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barWidth = math.max(6.0, math.min(width, width * (end - start)));
        final left = math.max(0.0, math.min(width * start, width - barWidth));
        return SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: barWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sunRow(BuildContext context, WeatherForecast forecast) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _metric(
              context,
              Icons.wb_twilight,
              '日出',
              clockLabel(forecast.sunrise),
            ),
            _metric(
              context,
              Icons.nightlight_outlined,
              '日落',
              clockLabel(forecast.sunset),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, WeatherForecast forecast) {
    final theme = Theme.of(context);
    return Text(
      '資料來源：中央氣象署 · 更新於 ${clockLabel(forecast.fetchedAt)}',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    final message = _locationUnavailable
        ? '無法取得目前位置，因此無法顯示天氣。請確認定位服務與定位權限已開啟。'
        : (_error ?? _genericWeatherError);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
      child: Column(
        children: [
          Icon(
            _locationUnavailable
                ? Icons.location_off_outlined
                : Icons.cloud_off_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _load(force: true),
            child: const Text('重試'),
          ),
        ],
      ),
    );
  }
}

/// Zero padded `HH:MM`, or `--:--` when the time is unknown.
///
/// Forecast times already carry the location's wall clock, so no timezone
/// conversion happens here.
String clockLabel(DateTime? time) {
  if (time == null) {
    return '--:--';
  }
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// `今天` / `明天` for the first two days, then `週三` style labels.
String dayLabel(DateTime date, int index) {
  if (index == 0) {
    return '今天';
  }
  if (index == 1) {
    return '明天';
  }
  // DateTime.weekday is 1 (Monday) through 7 (Sunday).
  return '週${_weekdayNames[date.weekday - 1]}';
}

const String _genericWeatherError = '無法載入天氣資料，請稍後再試。';
