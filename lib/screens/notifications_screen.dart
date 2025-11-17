import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['uid'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        actions: [
          if (userId != null && userId.isNotEmpty)
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(Icons.done_all),
              onPressed: () => _markAllAsRead(userId),
            ),
        ],
      ),
      body: userId == null || userId.isEmpty
          ? const _EmptyState(
              icon: Icons.notifications_off_outlined,
              message: 'Notifications are unavailable.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: userId)
                  .orderBy('timestamp', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _ErrorState(
                    error: snapshot.error.toString(),
                    onRetry: () => {},
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'No notifications yet.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final notification = docs[index];
                    final data = notification.data();
                    final isRead = data['isRead'] == true;
                    final type = (data['type'] ?? 'info').toString();
                    final title =
                        (data['title'] ?? 'Notification').toString().trim();
                    final message =
                        (data['message'] ?? '').toString().trim();
                    final priority =
                        (data['priority'] ?? 'normal').toString().toLowerCase();
                    final timestamp = data['timestamp'];

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _handleNotificationTap(
                        context,
                        notification.id,
                        data,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isRead
                              ? Colors.white
                              : const Color(0xFF0A4D68).withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _borderColorForPriority(priority),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _iconBackgroundForType(type),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _iconForType(type),
                                    color: _iconColorForType(type),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty
                                            ? 'Notification'
                                            : title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF0A4D68),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        message.isEmpty
                                            ? 'No additional details.'
                                            : message,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _PriorityChip(priority: priority),
                                Text(
                                  _formatTimestamp(timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    String notificationId,
    Map<String, dynamic> data,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('NotificationsScreen: Failed to mark as read: $error');
    }

    // Future enhancement: navigate based on data['navigation']
    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _markAllAsRead(String userId) async {
    try {
      final unreadSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadSnapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (error) {
      debugPrint('NotificationsScreen: Failed to mark all as read: $error');
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    DateTime? dateTime;
    if (timestamp == null) {
      dateTime = null;
    } else if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is String) {
      try {
        dateTime = DateTime.parse(timestamp);
      } catch (_) {
        dateTime = null;
      }
    }

    if (dateTime == null) {
      return 'Unknown time';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else {
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
    }
  }

  Color _borderColorForPriority(String priority) {
    switch (priority) {
      case 'critical':
        return Colors.redAccent.withOpacity(0.5);
      case 'high':
        return const Color(0xFFFFA726).withOpacity(0.5);
      default:
        return const Color(0xFF27AE60).withOpacity(0.4);
    }
  }

  Color _iconBackgroundForType(String type) {
    switch (type) {
      case 'success':
        return const Color(0xFF27AE60).withOpacity(0.12);
      case 'warning':
        return const Color(0xFFFFA726).withOpacity(0.12);
      case 'error':
        return Colors.redAccent.withOpacity(0.12);
      default:
        return const Color(0xFF0A4D68).withOpacity(0.12);
    }
  }

  Color _iconColorForType(String type) {
    switch (type) {
      case 'success':
        return const Color(0xFF27AE60);
      case 'warning':
        return const Color(0xFFFFA726);
      case 'error':
        return Colors.redAccent;
      default:
        return const Color(0xFF0A4D68);
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.notifications_none;
    }
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final label = priority == 'critical'
        ? 'Critical'
        : priority == 'high'
            ? 'High'
            : 'Normal';

    final color = priority == 'critical'
        ? Colors.redAccent
        : priority == 'high'
            ? const Color(0xFFFFA726)
            : const Color(0xFF27AE60);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

