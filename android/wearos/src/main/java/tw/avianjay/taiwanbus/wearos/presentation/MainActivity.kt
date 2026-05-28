package tw.avianjay.taiwanbus.wearos.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.TransformingLazyColumnScope
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.EdgeButton
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import kotlinx.coroutines.delay
import tw.avianjay.taiwanbus.wearos.data.FavoriteStop
import tw.avianjay.taiwanbus.wearos.data.RouteSearchResult
import tw.avianjay.taiwanbus.wearos.data.WearDataRepository
import tw.avianjay.taiwanbus.wearos.data.WearHomeState
import tw.avianjay.taiwanbus.wearos.data.WearRouteDetail
import tw.avianjay.taiwanbus.wearos.data.WearRoutePath
import tw.avianjay.taiwanbus.wearos.data.WearRouteStop
import tw.avianjay.taiwanbus.wearos.presentation.theme.AndroidTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WearDataRepository.ensureLoaded(applicationContext)
        setContent {
            AndroidTheme {
                WearApp(
                    state = WearDataRepository.state,
                    onRefresh = {
                        WearDataRepository.refresh(applicationContext)
                    },
                    onSearch = { query ->
                        WearDataRepository.searchRoutes(applicationContext, query)
                    },
                )
            }
        }
    }
}

private enum class WearScreen {
    Favorites,
    Search,
    RouteDetail,
}

@Composable
private fun WearApp(
    state: WearHomeState,
    onRefresh: () -> Unit,
    onSearch: suspend (String) -> List<RouteSearchResult>,
) {
    var screen by rememberSaveable { mutableStateOf(WearScreen.Favorites) }
    var selectedRoute by rememberSaveable { mutableStateOf<RouteSearchResult?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<RouteSearchResult>>(emptyList()) }
    var searchLoading by remember { mutableStateOf(false) }
    var searchError by remember { mutableStateOf<String?>(null) }

    var detailRefreshTrigger by remember { mutableStateOf(0) }
    var routeDetail by remember { mutableStateOf<WearRouteDetail?>(null) }
    var routeDetailLoading by remember { mutableStateOf(false) }
    var routeDetailError by remember { mutableStateOf<String?>(null) }
    var activePathIndex by remember { mutableStateOf(0) }
    val context = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(screen, query) {
        if (screen != WearScreen.Search) {
            searchLoading = false
            return@LaunchedEffect
        }

        val normalized = query.trim()
        if (normalized.isEmpty()) {
            searchResults = emptyList()
            searchLoading = false
            searchError = null
            return@LaunchedEffect
        }

        delay(250)
        searchLoading = true
        searchError = null
        runCatching {
            onSearch(normalized)
        }.onSuccess { results ->
            searchResults = results
            searchLoading = false
        }.onFailure { error ->
            searchResults = emptyList()
            searchLoading = false
            searchError = error.message ?: "搜尋失敗"
        }
    }

    LaunchedEffect(selectedRoute, detailRefreshTrigger) {
        val route = selectedRoute
        if (route == null) {
            routeDetail = null
            routeDetailLoading = false
            routeDetailError = null
            activePathIndex = 0
            return@LaunchedEffect
        }

        routeDetailLoading = true
        routeDetailError = null
        runCatching {
            WearDataRepository.fetchRouteDetail(context, route.routeId, route.provider)
        }.onSuccess { detail ->
            routeDetail = detail
            routeDetailLoading = false
        }.onFailure { error ->
            routeDetail = null
            routeDetailLoading = false
            routeDetailError = error.message ?: "載入路線資料失敗"
        }
    }

    AppScaffold {
        val listState = rememberTransformingLazyColumnState()
        val transformationSpec = rememberTransformationSpec()

        ScreenScaffold(
            scrollState = listState,
            edgeButton = {
                EdgeButton(
                    onClick = {
                        when (screen) {
                            WearScreen.RouteDetail -> {
                                screen = WearScreen.Search
                                selectedRoute = null
                            }
                            WearScreen.Search -> {
                                screen = WearScreen.Favorites
                            }
                            WearScreen.Favorites -> onRefresh()
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    ),
                ) {
                    Text(
                        when (screen) {
                            WearScreen.Search, WearScreen.RouteDetail -> "返回"
                            WearScreen.Favorites -> "整理"
                        }
                    )
                }
            },
        ) { contentPadding ->
            TransformingLazyColumn(contentPadding = contentPadding, state = listState) {
                item {
                    ListHeader(
                        modifier =
                            Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Column {
                            Text(
                                when (screen) {
                                    WearScreen.Favorites -> "我的最愛"
                                    WearScreen.Search -> "搜尋公車"
                                    WearScreen.RouteDetail -> selectedRoute?.routeName ?: "公車資料"
                                },
                            )
                            Text(
                                when (screen) {
                                    WearScreen.Search ->
                                        "使用即時網路 API"

                                    WearScreen.RouteDetail ->
                                        selectedRoute?.description ?: ""

                                    else -> when {
                                        state.settings.syncEnabled && state.hasSyncedFavorites ->
                                            "已同步最愛，即時到站資料來自網路"

                                        state.settings.syncEnabled ->
                                            "尚未同步最愛，搜尋功能仍可使用"

                                        else ->
                                            "在手機應用中開啟 Wear OS 同步"
                                    }
                                },
                            )
                        }
                    }
                }

                when (screen) {
                    WearScreen.Favorites -> {
                        favoritesContent(
                            state = state,
                            onOpenSearch = { screen = WearScreen.Search },
                        )
                    }

                    WearScreen.Search -> {
                        searchContent(
                            query = query,
                            results = searchResults,
                            loading = searchLoading,
                            error = searchError,
                            onQueryChange = { query = it },
                            onSelectRoute = { route ->
                                selectedRoute = route
                                screen = WearScreen.RouteDetail
                            },
                        )
                    }

                    WearScreen.RouteDetail -> {
                        routeDetailContent(
                            detail = routeDetail,
                            loading = routeDetailLoading,
                            error = routeDetailError,
                            activePathIndex = activePathIndex,
                            onTogglePath = {
                                val size = routeDetail?.paths?.size ?: 1
                                activePathIndex = (activePathIndex + 1) % size
                            },
                            onRefreshDetail = {
                                detailRefreshTrigger++
                            }
                        )
                    }
                }
            }
        }
    }
}

private fun TransformingLazyColumnScope.favoritesContent(
    state: WearHomeState,
    onOpenSearch: () -> Unit,
) {
    item {
        Button(
            onClick = onOpenSearch,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column {
                Text("搜尋公車")
                Text("即時搜尋，無需手機連線")
            }
        }
    }

    if (!state.settings.syncEnabled || state.favorites.isEmpty()) {
        item {
            WearInfoCard(
                title = if (state.settings.syncEnabled) {
                    "無最愛"
                } else {
                    "同步未開啟"
                },
                subtitle = if (state.settings.syncEnabled) {
                    "請在手機應用選擇最愛後再同步"
                } else {
                    "請在手機應用開啟 Wear OS 同步"
                },
            )
        }
        return
    }

    if (state.isRefreshing) {
        item {
            WearInfoCard(
                title = "整理中",
                subtitle = "載入即時到站資料...",
            )
        }
    }

    state.lastRefreshError?.let { error ->
        item {
            WearInfoCard(
                title = "整理失敗",
                subtitle = error,
            )
        }
    }

    state.favorites.forEach { favorite ->
        item {
            FavoriteArrivalCard(
                favorite = favorite,
                state = state,
            )
        }
    }

    state.lastRefreshAtMs?.let { refreshedAtMs ->
        item {
            WearInfoCard(
                title = "最後更新",
                subtitle = formatClockTime(refreshedAtMs),
            )
        }
    }
}

private fun TransformingLazyColumnScope.searchContent(
    query: String,
    results: List<RouteSearchResult>,
    loading: Boolean,
    error: String?,
    onQueryChange: (String) -> Unit,
    onSelectRoute: (RouteSearchResult) -> Unit,
) {
    item {
        SearchBox(
            value = query,
            onValueChange = onQueryChange,
        )
    }

    if (query.trim().isEmpty()) {
        item {
            WearInfoCard(
                title = "搜尋公車",
                subtitle = "輸入路線號碼搜尋",
            )
        }
        return
    }

    if (loading) {
        item {
            WearInfoCard(
                title = "搜尋中",
                subtitle = "查詢即時資料...",
            )
        }
        return
    }

    if (error != null) {
        item {
            WearInfoCard(
                title = "搜尋失敗",
                subtitle = error,
            )
        }
        return
    }

    if (results.isEmpty()) {
        item {
            WearInfoCard(
                title = "無結果",
                subtitle = "沒有符合的即時資料",
            )
        }
        return
    }

    results.forEach { route ->
        item {
            Button(
                onClick = { onSelectRoute(route) },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                ),
            ) {
                Column {
                    Text(route.routeName)
                    Text(route.description)
                    Text(route.provider)
                }
            }
        }
    }
}

@Composable
private fun FavoriteArrivalCard(
    favorite: FavoriteStop,
    state: WearHomeState,
) {
    val arrival = state.arrivalFor(favorite.id)
    Button(
        onClick = {},
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        ),
    ) {
        Column {
            Text(favorite.displayRouteName)
            Text(favorite.displayStopName)
            Text(arrival?.etaText ?: "--")
            arrival?.arrivalEpochMs?.let { arrivalAtMs ->
                Text(formatClockTime(arrivalAtMs))
            }
            Text(arrival?.statusText ?: favorite.groupName.ifBlank { favorite.provider })
        }
    }
}

private fun TransformingLazyColumnScope.routeDetailContent(
    detail: WearRouteDetail?,
    loading: Boolean,
    error: String?,
    activePathIndex: Int,
    onTogglePath: () -> Unit,
    onRefreshDetail: () -> Unit,
) {
    if (loading) {
        item {
            WearInfoCard(
                title = "載入中",
                subtitle = "查詢即時路線資料...",
            )
        }
        return
    }

    if (error != null) {
        item {
            WearInfoCard(
                title = "載入失敗",
                subtitle = error,
            )
        }
        item {
            Button(
                onClick = onRefreshDetail,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            ) {
                Text("重試")
            }
        }
        return
    }

    if (detail == null || detail.paths.isEmpty()) {
        item {
            WearInfoCard(
                title = "無資料",
                subtitle = "此路線暫無公車路徑資訊",
            )
        }
        return
    }

    val path = detail.paths.getOrNull(activePathIndex) ?: detail.paths.first()

    if (detail.paths.size > 1) {
        item {
            Button(
                onClick = onTogglePath,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                    contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
                )
            ) {
                Column {
                    Text("切換方向")
                    Text("目前: ${path.name}")
                }
            }
        }
    } else {
        item {
            WearInfoCard(
                title = "方向",
                subtitle = path.name,
            )
        }
    }

    item {
        Button(
            onClick = onRefreshDetail,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
                contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        ) {
            Text("重新整理")
        }
    }

    path.stops.forEach { stop ->
        item {
            RouteStopCard(stop = stop)
        }
    }
}

@Composable
private fun RouteStopCard(stop: WearRouteStop) {
    Button(
        onClick = {},
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
            contentColor = MaterialTheme.colorScheme.onSurface,
        ),
    ) {
        Column {
            Text(
                text = stop.name,
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stop.etaText,
                color = when {
                    stop.etaText == "即將到站" -> MaterialTheme.colorScheme.error
                    stop.etaText.contains("分") -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
                style = MaterialTheme.typography.bodyMedium
            )
            if (stop.statusText.isNotBlank()) {
                Text(
                    text = stop.statusText,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@Composable
private fun WearInfoCard(
    title: String,
    subtitle: String,
) {
    Button(
        onClick = {},
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
    ) {
        Column {
            Text(title)
            Text(subtitle)
        }
    }
}

@Composable
private fun SearchBox(
    value: String,
    onValueChange: (String) -> Unit,
) {
    val textStyle = TextStyle(
        color = MaterialTheme.colorScheme.onSurface,
    )
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        textStyle = textStyle,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Characters,
            imeAction = ImeAction.Search,
        ),
        decorationBox = { innerTextField ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = RoundedCornerShape(20.dp),
                    )
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                if (value.isEmpty()) {
                    Text("輸入路線號碼...")
                }
                innerTextField()
            }
        },
    )
}

private fun formatClockTime(timestampMs: Long): String {
    val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
    return formatter.format(Date(timestampMs))
}
