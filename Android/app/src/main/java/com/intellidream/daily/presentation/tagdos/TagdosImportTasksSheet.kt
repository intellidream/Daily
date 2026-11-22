package com.intellidream.daily.presentation.tagdos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.CheckBox
import androidx.compose.material.icons.rounded.CheckBoxOutlineBlank
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.TagDoStream
import com.intellidream.daily.model.TagdosParser
import com.intellidream.daily.network.ExternalTaskAccount
import com.intellidream.daily.network.ExternalTaskList
import com.intellidream.daily.network.ExternalTaskProvider
import com.intellidream.daily.network.ExternalTasksAuthException
import com.intellidream.daily.network.TagdosExternalTasksService
import kotlinx.coroutines.launch

private sealed interface AndroidTargetChoice {
    data class ReplaceStream(val streamId: String) : AndroidTargetChoice
    data class AppendToStream(val streamId: String) : AndroidTargetChoice
    data object NewStream : AndroidTargetChoice

    fun shortLabel(streams: List<TagDoStream>): String = when (this) {
        is ReplaceStream -> streams.firstOrNull { it.id == streamId }?.let {
            "Replace S${it.orderIndex + 1} (${it.displayTitle})"
        } ?: "Replace Stream"
        is AppendToStream -> streams.firstOrNull { it.id == streamId }?.let {
            "Append S${it.orderIndex + 1} (${it.displayTitle})"
        } ?: "Append Stream"
        is NewStream -> "+ New Stream"
    }
}

private data class AndroidImportDraft(
    val id: String,
    val originalTitle: String,
    val originalNotes: String?,
    val isHighImportance: Boolean,
    val isAlreadyDsl: Boolean,
    val editedTag: String,
    val isSelected: Boolean = false,
    val targetChoice: AndroidTargetChoice,
    val newStreamTitle: String = ""
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagdosImportTasksSheet(
    repository: TagdosRepository,
    initialStreamId: String?,
    onImported: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val streams by repository.streams.collectAsState()
    val allAccounts by TagdosExternalTasksService.accounts.collectAsState()
    val isLoadingAccounts by TagdosExternalTasksService.isLoadingAccounts.collectAsState()

    var selectedProvider by remember { mutableStateOf(ExternalTaskProvider.MicrosoftToDo) }
    var selectedAccountId by remember { mutableStateOf<String?>(null) }
    var taskLists by remember { mutableStateOf<List<ExternalTaskList>>(emptyList()) }
    var selectedListId by remember { mutableStateOf<String?>(null) }
    val stagedByTaskKey = remember { mutableStateMapOf<String, AndroidImportDraft>() }
    var visibleTaskKeys by remember { mutableStateOf<List<String>>(emptyList()) }

    var isAuthenticating by remember { mutableStateOf(false) }
    var isLoadingLists by remember { mutableStateOf(false) }
    var isLoadingTasks by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var needsReauth by remember { mutableStateOf(false) }

    var defaultTargetChoice by remember {
        val fallbackId = initialStreamId ?: streams.firstOrNull()?.id
        mutableStateOf<AndroidTargetChoice>(
            if (fallbackId != null) AndroidTargetChoice.ReplaceStream(fallbackId) else AndroidTargetChoice.NewStream
        )
    }

    fun resolveValidChoice(choice: AndroidTargetChoice): AndroidTargetChoice = when (choice) {
        is AndroidTargetChoice.ReplaceStream ->
            if (streams.any { it.id == choice.streamId }) choice else AndroidTargetChoice.NewStream
        is AndroidTargetChoice.AppendToStream ->
            if (streams.any { it.id == choice.streamId }) choice else AndroidTargetChoice.NewStream
        is AndroidTargetChoice.NewStream -> choice
    }

    val providerAccounts = remember(allAccounts, selectedProvider) {
        allAccounts.filter { it.provider == selectedProvider }
    }
    val selectedAccount = remember(providerAccounts, selectedAccountId) {
        providerAccounts.firstOrNull { it.id == selectedAccountId } ?: providerAccounts.firstOrNull()
    }

    suspend fun loadTasks(account: ExternalTaskAccount, listId: String) {
        isLoadingTasks = true
        errorMessage = null
        needsReauth = false
        try {
            val items = TagdosExternalTasksService.fetchTasks(account, listId)
            val fallbackTarget = resolveValidChoice(defaultTargetChoice)
            val nextKeys = mutableListOf<String>()
            items.forEach { item ->
                val key = "${account.provider.name}::${account.id}::$listId::${item.id}"
                nextKeys.add(key)
                if (!stagedByTaskKey.containsKey(key)) {
                    val (tagOrDsl, isDsl, _) = TagdosParser.prepareImportItem(
                        title = item.title,
                        notes = item.notes,
                        isHighImportance = item.isHighImportance
                    )
                    stagedByTaskKey[key] = AndroidImportDraft(
                        id = key,
                        originalTitle = item.title,
                        originalNotes = item.notes,
                        isHighImportance = item.isHighImportance,
                        isAlreadyDsl = isDsl,
                        editedTag = tagOrDsl,
                        isSelected = false,
                        targetChoice = fallbackTarget,
                        newStreamTitle = ""
                    )
                }
            }
            visibleTaskKeys = nextKeys
        } catch (e: ExternalTasksAuthException) {
            errorMessage = e.message
            needsReauth = e.needsReauth
        } catch (e: Exception) {
            errorMessage = e.message ?: "Failed to load tasks."
        } finally {
            isLoadingTasks = false
        }
    }

    suspend fun loadLists(account: ExternalTaskAccount) {
        isLoadingLists = true
        errorMessage = null
        needsReauth = false
        visibleTaskKeys = emptyList()
        try {
            val lists = TagdosExternalTasksService.fetchTaskLists(account)
            taskLists = lists
            val def = lists.firstOrNull { it.isDefault } ?: lists.firstOrNull()
            selectedListId = def?.id
            if (def != null) {
                loadTasks(account, def.id)
            }
        } catch (e: ExternalTasksAuthException) {
            errorMessage = e.message
            needsReauth = e.needsReauth
        } catch (e: Exception) {
            errorMessage = e.message ?: "Failed to load lists."
        } finally {
            isLoadingLists = false
        }
    }

    fun launchSignIn() {
        scope.launch {
            isAuthenticating = true
            errorMessage = null
            needsReauth = false
            try {
                val acc = TagdosExternalTasksService.signIn(context, selectedProvider)
                selectedAccountId = acc.id
                loadLists(acc)
            } catch (e: Exception) {
                errorMessage = e.message ?: "Sign-in failed."
            } finally {
                isAuthenticating = false
            }
        }
    }

    LaunchedEffect(Unit) {
        if (resolveValidChoice(defaultTargetChoice) == AndroidTargetChoice.NewStream) {
            val fallbackId = initialStreamId ?: streams.firstOrNull()?.id
            if (fallbackId != null) {
                defaultTargetChoice = AndroidTargetChoice.ReplaceStream(fallbackId)
            }
        }
        TagdosExternalTasksService.refreshAvailableAccounts()
        val accountsNow = TagdosExternalTasksService.accounts.value
        val currentAcc = accountsNow.firstOrNull { it.provider == selectedProvider } ?: accountsNow.firstOrNull()
        if (currentAcc != null) {
            selectedProvider = currentAcc.provider
            selectedAccountId = currentAcc.id
            loadLists(currentAcc)
        }
    }

    val visibleSet = visibleTaskKeys.toSet()
    val visibleSelected = visibleTaskKeys.mapNotNull { stagedByTaskKey[it] }
        .filter { it.isSelected && it.editedTag.isNotBlank() }
    val offListSelected = stagedByTaskKey.values
        .filter { !visibleSet.contains(it.id) && it.isSelected && it.editedTag.isNotBlank() }
        .sortedBy { it.id }
    val selectedDraftsOrdered = visibleSelected + offListSelected
    val selectedCount = selectedDraftsOrdered.size
    val offListSelectedCount = offListSelected.size

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF060E1E),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                }
                Text(
                    text = "Import Tasks",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Button(
                    onClick = {
                        val chosen = selectedDraftsOrdered
                        if (chosen.isNotEmpty()) {
                            val batchItems = chosen.map { draft ->
                                val tag = draft.editedTag.trim()
                                val notes = draft.originalNotes?.trim().orEmpty()
                                val memoLine: String? = if (draft.isAlreadyDsl) {
                                    notes.takeIf { it.isNotEmpty() }
                                } else {
                                    if (notes.isEmpty()) "• [$tag] ${draft.originalTitle}"
                                    else "• [$tag] ${draft.originalTitle} — $notes"
                                }
                                val target: TagdosRepository.TagdosTaskImportTarget = when (val c = resolveValidChoice(draft.targetChoice)) {
                                    is AndroidTargetChoice.ReplaceStream ->
                                        TagdosRepository.TagdosTaskImportTarget.ReplaceStream(c.streamId)
                                    is AndroidTargetChoice.AppendToStream ->
                                        TagdosRepository.TagdosTaskImportTarget.AppendToStream(c.streamId)
                                    is AndroidTargetChoice.NewStream ->
                                        TagdosRepository.TagdosTaskImportTarget.NewStream(draft.newStreamTitle)
                                }
                                TagdosRepository.TagdosTaskImportItem(
                                    dslOrTag = tag,
                                    memoLine = memoLine,
                                    target = target
                                )
                            }
                            val resultId = repository.importExternalTaskBatch(batchItems)
                            if (resultId != null) {
                                onImported(resultId)
                            }
                            onDismiss()
                        }
                    },
                    enabled = selectedCount > 0,
                    colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                    shape = CircleShape
                ) {
                    Text(
                        text = "Import ($selectedCount)",
                        color = Color.Black,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp
                    )
                }
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Provider Switcher
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ExternalTaskProvider.entries.forEach { provider ->
                        val isSelected = selectedProvider == provider
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .background(
                                    if (isSelected) ThemeColors.accentPurple.copy(alpha = 0.38f)
                                    else Color.White.copy(alpha = 0.06f)
                                )
                                .border(
                                    1.dp,
                                    if (isSelected) ThemeColors.accentPurple else Color.White.copy(alpha = 0.12f),
                                    RoundedCornerShape(12.dp)
                                )
                                .clickable {
                                    selectedProvider = provider
                                    errorMessage = null
                                    needsReauth = false
                                    taskLists = emptyList()
                                    selectedListId = null
                                    visibleTaskKeys = emptyList()
                                    val nextAcc = allAccounts.firstOrNull { it.provider == provider }
                                    selectedAccountId = nextAcc?.id
                                    if (nextAcc != null) {
                                        scope.launch { loadLists(nextAcc) }
                                    }
                                }
                                .padding(vertical = 11.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = provider.displayName,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.65f)
                            )
                        }
                    }
                }

                // Account Section
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "ACCOUNT",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.5f)
                    )
                    if (providerAccounts.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.clickable { launchSignIn() }
                        ) {
                            Icon(Icons.Rounded.AddCircle, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(13.dp))
                            Text("Add Account", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = ThemeColors.accentCyan)
                        }
                    }
                }

                if (isLoadingAccounts) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                        Text("Checking connected accounts...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                    }
                } else if (providerAccounts.isEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.05f))
                            .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(14.dp))
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = "Connect your ${selectedProvider.displayName} account to browse lists and import tasks into TagDoS.",
                            fontSize = 12.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                        Button(
                            onClick = { launchSignIn() },
                            enabled = !isAuthenticating,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text(
                                text = if (isAuthenticating) "Waiting for Browser..." else "Sign in with ${selectedProvider.displayName}",
                                color = Color.Black,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                } else {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        providerAccounts.forEach { acc ->
                            val isSelected = selectedAccount?.id == acc.id
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(if (isSelected) ThemeColors.accentCyan.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.06f))
                                    .border(1.dp, if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.12f), CircleShape)
                                    .clickable {
                                        selectedAccountId = acc.id
                                        scope.launch { loadLists(acc) }
                                    }
                                    .padding(horizontal = 10.dp, vertical = 7.dp)
                            ) {
                                Icon(
                                    imageVector = if (isSelected) Icons.Rounded.CheckCircle else Icons.Rounded.Person,
                                    contentDescription = null,
                                    tint = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.5f),
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(acc.email, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                            }
                        }
                    }
                }

                errorMessage?.let { err ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(ThemeColors.accentPink.copy(alpha = 0.12f))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(err, fontSize = 11.5.sp, color = ThemeColors.accentPink)
                        if (needsReauth) {
                            Button(
                                onClick = { launchSignIn() },
                                colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                                shape = CircleShape
                            ) {
                                Text("Re-authenticate & Grant Tasks Access", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 11.5.sp)
                            }
                        }
                    }
                }

                // Lists & Tasks
                if (selectedAccount != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("LISTS & TASKS", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.5f))
                        IconButton(onClick = { scope.launch { loadLists(selectedAccount) } }, modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Rounded.Refresh, "Refresh", tint = ThemeColors.accentCyan, modifier = Modifier.size(15.dp))
                        }
                    }

                    if (isLoadingLists) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                            Text("Loading task lists...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                        }
                    } else if (taskLists.isNotEmpty()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            taskLists.forEach { list ->
                                val isSel = selectedListId == list.id
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(if (isSel) ThemeColors.accentCyan else Color.White.copy(alpha = 0.08f))
                                        .clickable {
                                            selectedListId = list.id
                                            scope.launch { loadTasks(selectedAccount, list.id) }
                                        }
                                        .padding(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text(
                                        text = list.title,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (isSel) Color.Black else Color.White
                                    )
                                }
                            }
                        }

                        if (isLoadingTasks) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                                Text("Fetching active tasks...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                            }
                        } else if (visibleTaskKeys.isEmpty()) {
                            Text("No active tasks in this list.", fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f))
                        } else {
                            // Default target bar
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(Color.White.copy(alpha = 0.045f))
                                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp))
                                    .padding(horizontal = 10.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = "Default:",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White.copy(alpha = 0.65f)
                                )
                                AndroidTargetDropdownPill(
                                    choice = resolveValidChoice(defaultTargetChoice),
                                    streams = streams,
                                    onSelect = { defaultTargetChoice = it }
                                )
                                Spacer(modifier = Modifier.weight(1f))
                                val visibleCheckedCount = visibleTaskKeys.count { stagedByTaskKey[it]?.isSelected == true }
                                if (visibleCheckedCount > 0) {
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(ThemeColors.accentPurple.copy(alpha = 0.45f))
                                            .clickable {
                                                val chosen = resolveValidChoice(defaultTargetChoice)
                                                visibleTaskKeys.forEach { key ->
                                                    val cur = stagedByTaskKey[key]
                                                    if (cur != null && cur.isSelected) {
                                                        stagedByTaskKey[key] = cur.copy(targetChoice = chosen)
                                                    }
                                                }
                                            }
                                            .padding(horizontal = 9.dp, vertical = 5.dp)
                                    ) {
                                        Text(
                                            text = "Apply ($visibleCheckedCount)",
                                            fontSize = 10.5.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                    }
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("${visibleTaskKeys.size} active tasks", fontSize = 11.sp, color = Color.White.copy(alpha = 0.6f))
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(
                                        text = "Select All",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan,
                                        modifier = Modifier.clickable {
                                            visibleTaskKeys.forEach { key ->
                                                stagedByTaskKey[key]?.let { stagedByTaskKey[key] = it.copy(isSelected = true) }
                                            }
                                        }
                                    )
                                    Text(
                                        text = "Clear",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White.copy(alpha = 0.6f),
                                        modifier = Modifier.clickable {
                                            visibleTaskKeys.forEach { key ->
                                                stagedByTaskKey[key]?.let { stagedByTaskKey[key] = it.copy(isSelected = false) }
                                            }
                                        }
                                    )
                                }
                            }

                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                visibleTaskKeys.forEach { key ->
                                    val draft = stagedByTaskKey[key] ?: return@forEach
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(Color.White.copy(alpha = if (draft.isSelected) 0.055f else 0.025f))
                                            .border(1.dp, Color.White.copy(alpha = if (draft.isSelected) 0.16f else 0.08f), RoundedCornerShape(12.dp))
                                            .padding(10.dp),
                                        verticalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            Icon(
                                                imageVector = if (draft.isSelected) Icons.Rounded.CheckBox else Icons.Rounded.CheckBoxOutlineBlank,
                                                contentDescription = null,
                                                tint = if (draft.isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.4f),
                                                modifier = Modifier
                                                    .size(20.dp)
                                                    .clickable { stagedByTaskKey[key] = draft.copy(isSelected = !draft.isSelected) }
                                            )

                                            OutlinedTextField(
                                                value = draft.editedTag,
                                                onValueChange = { stagedByTaskKey[key] = draft.copy(editedTag = it) },
                                                singleLine = true,
                                                modifier = Modifier.weight(1f),
                                                textStyle = TextStyle(
                                                    fontFamily = FontFamily.Monospace,
                                                    fontSize = 12.5.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    color = Color.White
                                                ),
                                                colors = OutlinedTextFieldDefaults.colors(
                                                    focusedBorderColor = ThemeColors.accentCyan,
                                                    unfocusedBorderColor = Color.White.copy(alpha = 0.14f)
                                                ),
                                                shape = RoundedCornerShape(8.dp)
                                            )

                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background((if (draft.isAlreadyDsl) ThemeColors.accentCyan else ThemeColors.accentOrange).copy(alpha = 0.15f))
                                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                                            ) {
                                                Text(
                                                    text = if (draft.isAlreadyDsl) "DSL" else "AUTO + MEMO",
                                                    fontSize = 9.sp,
                                                    fontWeight = FontWeight.Black,
                                                    color = if (draft.isAlreadyDsl) ThemeColors.accentCyan else ThemeColors.accentOrange
                                                )
                                            }
                                        }

                                        if (!draft.isAlreadyDsl) {
                                            Text(
                                                text = draft.originalTitle,
                                                fontSize = 11.sp,
                                                color = Color.White.copy(alpha = 0.65f),
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.padding(start = 28.dp)
                                            )
                                        }
                                        draft.originalNotes?.takeIf { it.isNotBlank() }?.let { notes ->
                                            Text(
                                                text = notes,
                                                fontSize = 10.5.sp,
                                                color = Color.White.copy(alpha = 0.45f),
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.padding(start = 28.dp)
                                            )
                                        }

                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(start = 28.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            AndroidTargetDropdownPill(
                                                choice = resolveValidChoice(draft.targetChoice),
                                                streams = streams,
                                                onSelect = { chosen ->
                                                    stagedByTaskKey[key] = draft.copy(
                                                        targetChoice = chosen,
                                                        isSelected = true
                                                    )
                                                }
                                            )

                                            if (resolveValidChoice(draft.targetChoice) is AndroidTargetChoice.NewStream) {
                                                OutlinedTextField(
                                                    value = draft.newStreamTitle,
                                                    onValueChange = { stagedByTaskKey[key] = draft.copy(newStreamTitle = it) },
                                                    placeholder = { Text("Optional title...", fontSize = 11.sp) },
                                                    singleLine = true,
                                                    modifier = Modifier.weight(1f),
                                                    textStyle = TextStyle(fontSize = 11.sp, color = Color.White),
                                                    colors = OutlinedTextFieldDefaults.colors(
                                                        focusedBorderColor = ThemeColors.accentCyan,
                                                        unfocusedBorderColor = Color.White.copy(alpha = 0.14f)
                                                    ),
                                                    shape = RoundedCornerShape(6.dp)
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Batch Summary Card
                    if (selectedCount > 0) {
                        val groupedCounts = linkedMapOf<AndroidTargetChoice, Int>()
                        selectedDraftsOrdered.forEach { d ->
                            val c = resolveValidChoice(d.targetChoice)
                            groupedCounts[c] = (groupedCounts[c] ?: 0) + 1
                        }
                        val hasReplace = groupedCounts.keys.any { it is AndroidTargetChoice.ReplaceStream }

                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color.White.copy(alpha = 0.04f))
                                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "BATCH SUMMARY ($selectedCount TASK${if (selectedCount == 1) "" else "S"})",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White.copy(alpha = 0.5f)
                                )
                                if (offListSelectedCount > 0) {
                                    Text(
                                        text = "$offListSelectedCount from other list${if (offListSelectedCount == 1) "" else "s"}",
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan
                                    )
                                }
                            }

                            groupedCounts.forEach { (choice, count) ->
                                Text(
                                    text = "• $count task${if (count == 1) "" else "s"} → ${choice.shortLabel(streams)}",
                                    fontSize = 11.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White.copy(alpha = 0.88f)
                                )
                            }

                            if (hasReplace) {
                                Text(
                                    text = "Note: Replace targets clear existing pills and active memos on those streams before combining the mapped tasks.",
                                    fontSize = 10.5.sp,
                                    color = ThemeColors.accentOrange
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@Composable
private fun AndroidTargetDropdownPill(
    choice: AndroidTargetChoice,
    streams: List<TagDoStream>,
    onSelect: (AndroidTargetChoice) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val isReplace = choice is AndroidTargetChoice.ReplaceStream
    val tint = if (isReplace) ThemeColors.accentOrange else ThemeColors.accentCyan

    Box {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(tint.copy(alpha = 0.15f))
                .clickable { expanded = true }
                .padding(horizontal = 9.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = choice.shortLabel(streams),
                fontSize = 10.5.sp,
                fontWeight = FontWeight.Bold,
                color = tint,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Icon(
                imageVector = Icons.Rounded.ArrowDropDown,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(16.dp)
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            streams.forEach { s ->
                DropdownMenuItem(
                    text = { Text("Replace S${s.orderIndex + 1}: ${s.displayTitle}") },
                    onClick = {
                        expanded = false
                        onSelect(AndroidTargetChoice.ReplaceStream(s.id))
                    }
                )
            }
            HorizontalDivider()
            streams.forEach { s ->
                DropdownMenuItem(
                    text = { Text("Append S${s.orderIndex + 1}: ${s.displayTitle}") },
                    onClick = {
                        expanded = false
                        onSelect(AndroidTargetChoice.AppendToStream(s.id))
                    }
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text("+ New Stream") },
                onClick = {
                    expanded = false
                    onSelect(AndroidTargetChoice.NewStream)
                }
            )
        }
    }
}
