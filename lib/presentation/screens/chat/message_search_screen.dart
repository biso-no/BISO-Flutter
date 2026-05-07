import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chat_model.dart';
import 'chat_list_screen.dart';
import 'chat_conversation_screen.dart';

class MessageSearchScreen extends ConsumerStatefulWidget {
  final ChatModel chat;

  const MessageSearchScreen({super.key, required this.chat});

  @override
  ConsumerState<MessageSearchScreen> createState() =>
      _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatMessageModel> _searchResults = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      _searchQuery = query;
      _searchMessages(query);
    }
  }

  Future<void> _searchMessages(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final chatService = ref.read(chatServiceProvider);
      final results = await chatService.searchMessages(
        chatId: widget.chat.id,
        query: query,
        limit: 50,
      );

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Search Messages'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search messages...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.surface,
              ),
              autofocus: true,
            ),
          ),

          // Search results
          Expanded(child: _buildSearchResults()),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: AppColors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(
              'Start typing to search messages',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.message_outlined,
              size: 64,
              color: AppColors.onSurfaceVariant,
            ),
            SizedBox(height: 16),
            Text(
              'No messages found',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final message = _searchResults[index];
        return _MessageSearchResult(
          message: message,
          searchQuery: _searchQuery,
          onTap: () {
            // Navigate back to chat and scroll to message
            context.pop();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ChatConversationScreen(
                  chat: widget.chat,
                  scrollToMessageId: message.id,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MessageSearchResult extends StatelessWidget {
  final ChatMessageModel message;
  final String searchQuery;
  final VoidCallback onTap;

  const _MessageSearchResult({
    required this.message,
    required this.searchQuery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.subtleBlue,
        child: Text(
          message.senderName.isNotEmpty
              ? message.senderName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: AppColors.defaultBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        message.senderName,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _highlightSearchTerm(message.content, searchQuery),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMM dd, yyyy HH:mm').format(message.timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _highlightSearchTerm(String text, String searchTerm) {
    if (searchTerm.isEmpty) return text;

    // For now, just return the text
    // In a full implementation, you'd use RichText with highlighted spans
    return text;
  }
}
