import 'dart:convert';
import 'dart:io';

import 'package:githubinsights/constants.dart';
import 'package:http/http.dart' as http;

class GitOperations {
  final String token;

  GitOperations({required this.token});

  Map<String, String> get _defaultHeaders => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<List<dynamic>> _getPaginatedList(String url) async {
    final items = <dynamic>[];
    var page = 1;

    while (true) {
      final separator = url.contains('?') ? '&' : '?';
      final paginatedUrl = '$url${separator}page=$page&per_page=100';
      final response = await http.get(
        Uri.parse(paginatedUrl),
        headers: _defaultHeaders,
      );

      printInDebug('Paginated request: $paginatedUrl -> ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception(
          'Failed paginated GitHub request ($paginatedUrl): ${response.statusCode} ${response.body}',
        );
      }

      final pageItems = json.decode(response.body) as List<dynamic>;
      items.addAll(pageItems);

      if (pageItems.length < 100) {
        return items;
      }

      page++;
    }
  }

  Map<String, dynamic> _withRoleName(
    Map<String, dynamic> user,
    String roleName,
  ) {
    return {
      ...user,
      'role_name': (user['role_name'] as String?)?.isNotEmpty == true
          ? user['role_name']
          : roleName,
    };
  }

  List<dynamic> _mergeUniqueUsers(List<List<dynamic>> userLists) {
    final merged = <String, Map<String, dynamic>>{};

    for (final users in userLists) {
      for (final user in users) {
        if (user is! Map) {
          continue;
        }

        final userMap = Map<String, dynamic>.from(user as Map);
        final login = (userMap['login'] ?? '') as String;
        if (login.isEmpty) {
          continue;
        }

        final existing = merged[login];
        if (existing == null) {
          merged[login] = userMap;
          continue;
        }

        merged[login] = {
          ...userMap,
          ...existing,
          if ((existing['role_name'] as String?)?.isNotEmpty == true)
            'role_name': existing['role_name'],
          if ((existing['permissions'] as Map?)?.isNotEmpty == true)
            'permissions': existing['permissions'],
        };
      }
    }

    return merged.values.toList()
      ..sort((a, b) => ((a['login'] ?? '') as String).compareTo((b['login'] ?? '') as String));
  }

  // Fetch full user information
  Future<Map<String, dynamic>> getUserInfo() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: _defaultHeaders,
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load user information: ${response.body}');
    }
  }

  // Fetch user's organizations
  Future<List<dynamic>> getUserOrganizations() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user/orgs'),
      headers: _defaultHeaders,
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load user organizations: ${response.body}');
    }
  }

  // Fetch repositories for a specific organization
  Future<List<dynamic>> getOrganizationRepositories(String orgName) async {
    final repos = <dynamic>[];
    var page = 1;

    while (true) {
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/orgs/$orgName/repos?page=$page&per_page=100',
        ),
        headers: _defaultHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load organization repositories: ${response.body}',
        );
      }

      final pageRepos = json.decode(response.body) as List<dynamic>;
      repos.addAll(pageRepos);

      if (pageRepos.length < 100) {
        return repos;
      }

      page++;
    }
  }

  // Fetch all repositories (user + organizations) with pagination
  Future<List<dynamic>> getAllRepositories({int perPage = 100}) async {
    final allRepos = <dynamic>[];
    
    // Get user repositories
    try {
      final userRepos = await listRepositories(true); // Include private repos
      allRepos.addAll(userRepos);
    } catch (e) {
      printInDebug('Error fetching user repositories: $e');
    }
    
    // Get organization repositories
    try {
      final orgs = await getUserOrganizations();
      for (final org in orgs) {
        try {
          final orgRepos = await getOrganizationRepositories(org['login']);
          allRepos.addAll(orgRepos);
        } catch (e) {
          printInDebug('Error fetching repositories for org ${org['login']}: $e');
        }
      }
    } catch (e) {
      printInDebug('Error fetching organizations: $e');
    }
    
    return allRepos;
  }

  // Fetch repositories with pagination support
  Future<List<dynamic>> getRepositoriesWithPagination({
    required String type, // 'user' or 'org'
    String? orgName,
    int page = 1,
    int perPage = 100,
    String? visibility, // 'all', 'public', 'private'
  }) async {
    String url;
    if (type == 'user') {
      url = 'https://api.github.com/user/repos?page=$page&per_page=$perPage';
      if (visibility != null) {
        url += '&visibility=$visibility';
      }
    } else if (type == 'org' && orgName != null) {
      url = 'https://api.github.com/orgs/$orgName/repos?page=$page&per_page=$perPage';
      if (visibility != null) {
        url += '&type=$visibility';
      }
    } else {
      throw Exception('Invalid parameters for repository fetching');
    }

    final response = await http.get(
      Uri.parse(url),
      headers: _defaultHeaders,
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load repositories: ${response.body}');
    }
  }

  Future<List<dynamic>> listRepositories(bool showPrivateRepos) async {
    final repos = <dynamic>[];
    var page = 1;

    while (true) {
      final visibilityQuery = showPrivateRepos ? '&visibility=all' : '';
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/user/repos?page=$page&per_page=100$visibilityQuery',
        ),
        headers: _defaultHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load repositories: ${response.body}');
      }

      final pageRepos = json.decode(response.body) as List<dynamic>;
      repos.addAll(pageRepos);

      if (pageRepos.length < 100) {
        return repos;
      }

      page++;
    }
  }

  Future<void> createRepository(String repoName, bool isPrivate) async {
    final response = await http.post(
      Uri.parse('https://api.github.com/user/repos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': repoName,
        'private': isPrivate,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create repository');
    }
  }

  Future<void> addFileToRepo(String owner, String repo, String path, File file,
      String commitMessage) async {
    List<int> fileBytes = await file.readAsBytes();
    String base64Content = base64Encode(fileBytes);

    final response = await http.put(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'message': commitMessage,
        'content': base64Content,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to add file to repository: ${response.body}');
    }
  }

  Future<dynamic> getRepoContents(
      String owner, String repo, String path) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get repository contents');
    }
  }

  Future<void> updateFileInRepo(String owner, String repo, String path,
      String newContent, String commitMessage) async {
    final apiUrl = 'https://api.github.com/repos/$owner/$repo/contents/$path';

    // Step 1: Get the current file contents
    final getResponse = await http.get(
      Uri.parse(apiUrl),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (getResponse.statusCode != 200) {
      throw Exception('Failed to get file: ${getResponse.body}');
    }

    final fileInfo = json.decode(getResponse.body);
    final String sha = fileInfo['sha'];

    // Step 2 & 3: Update content and create a commit
    final updateResponse = await http.put(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'message': commitMessage,
        'content': base64Encode(utf8.encode(newContent)),
        'sha': sha,
      }),
    );

    if (updateResponse.statusCode != 200) {
      throw Exception('Failed to update file: ${updateResponse.body}');
    }

    printInDebug('File updated successfully');
  }

  Future<List<dynamic>> getRepoCollaborators(String owner, String repo) async {
    printInDebug('Fetching collaborators for $owner/$repo');
    final url = 'https://api.github.com/repos/$owner/$repo/collaborators';
    printInDebug('API URL: $url');

    final response = await http.get(Uri.parse('$url?page=1&per_page=100'), headers: _defaultHeaders);

    printInDebug('Response status: ${response.statusCode}');
    printInDebug('Response body length: ${response.body.length}');
    printInDebug('Response headers: ${response.headers}');

    if (response.statusCode == 200) {
      final data = await _getPaginatedList(url);
      printInDebug('Successfully fetched ${data.length} collaborators for $owner/$repo');
      
      // Debug: Show first few collaborators
      if (data.isNotEmpty) {
        printInDebug('First collaborator data: ${data.first}');
        if (data.length > 1) {
          printInDebug('Second collaborator data: ${data[1]}');
        }
        if (data.length > 2) {
          printInDebug('Third collaborator data: ${data[2]}');
        }
      }
      
      return data;
    } else if (response.statusCode == 404) {
      printInDebug('Repository not found or no access: $owner/$repo');
      return [];
    } else if (response.statusCode == 403) {
      printInDebug('Access forbidden - may need different permissions for $owner/$repo');
      // Try to fetch contributors instead
      printInDebug('Trying to fetch contributors instead...');
      return await getRepoContributors(owner, repo);
    } else if (response.statusCode == 401) {
      printInDebug('Unauthorized - token may be invalid or expired');
      throw Exception('Unauthorized access to GitHub API. Please check your token.');
    } else {
      printInDebug('Error response body: ${response.body}');
      throw Exception(
          'Failed to fetch collaborators for repository $repo (Status: ${response.statusCode}): ${response.body}');
    }
  }

  // Fallback method to fetch contributors if collaborators endpoint fails
  Future<List<dynamic>> getRepoContributors(String owner, String repo) async {
    printInDebug('Fetching contributors for $owner/$repo');
    final url = 'https://api.github.com/repos/$owner/$repo/contributors';
    printInDebug('Contributors API URL: $url');

    final response =
        await http.get(Uri.parse('$url?page=1&per_page=100'), headers: _defaultHeaders);

    printInDebug('Contributors response status: ${response.statusCode}');
    printInDebug('Contributors response body length: ${response.body.length}');

    if (response.statusCode == 200) {
      final data = await _getPaginatedList(url);
      printInDebug('Successfully fetched ${data.length} contributors for $owner/$repo');
      return data;
    } else {
      printInDebug('Failed to fetch contributors: ${response.statusCode} - ${response.body}');
      return [];
    }
  }

  Future<List<dynamic>> getRepoPullRequestAuthors(String owner, String repo) async {
    printInDebug('Fetching pull request authors for $owner/$repo');
    final url = 'https://api.github.com/repos/$owner/$repo/pulls?state=all';
    printInDebug('Pull requests API URL: $url');

    final response =
        await http.get(Uri.parse('$url&page=1&per_page=100'), headers: _defaultHeaders);

    printInDebug('Pull requests response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final pullRequests = await _getPaginatedList(url);
      final authors = <dynamic>[];

      for (final pr in pullRequests) {
        if (pr is! Map) {
          continue;
        }

        final user = pr['user'];
        if (user is! Map) {
          continue;
        }

        authors.add(_withRoleName(Map<String, dynamic>.from(user), 'Pull request author'));
      }

      printInDebug('Successfully fetched ${authors.length} PR authors for $owner/$repo');
      return authors;
    }

    printInDebug(
      'Failed to fetch pull request authors: ${response.statusCode} - ${response.body}',
    );
    return [];
  }

  // Fetch collaborators for multiple repositories
  Future<Map<String, List<dynamic>>> getCollaboratorsForSelectedRepos(
      List<Map<String, String>> selectedRepos) async {
    printInDebug('getCollaboratorsForSelectedRepos called with ${selectedRepos.length} repositories');
    final collaboratorsMap = <String, List<dynamic>>{};

    for (final repoInfo in selectedRepos) {
      final owner = repoInfo['owner']!;
      final repo = repoInfo['repo']!;
      printInDebug('Processing repository: $owner/$repo');

      try {
        final collaborators = await getRepoCollaborators(owner, repo);
        final contributors = await getRepoContributors(owner, repo);
        final pullRequestAuthors = await getRepoPullRequestAuthors(owner, repo);

        collaboratorsMap[repo] = _mergeUniqueUsers([
          collaborators
              .map((user) => _withRoleName(Map<String, dynamic>.from(user as Map), 'Collaborator'))
              .toList(),
          contributors
              .map((user) => _withRoleName(Map<String, dynamic>.from(user as Map), 'Contributor'))
              .toList(),
          pullRequestAuthors,
        ]);
        printInDebug(
          'Successfully added ${collaboratorsMap[repo]!.length} combined collaborators for $repo',
        );
      } catch (e) {
        printInDebug('Error fetching collaborators for $repo: $e');
        // Continue with other repositories even if one fails
        collaboratorsMap[repo] = [];
      }
    }

    printInDebug('Final collaborators map: ${collaboratorsMap.keys.toList()}');
    for (final entry in collaboratorsMap.entries) {
      printInDebug('${entry.key}: ${entry.value.length} collaborators');
    }

    return collaboratorsMap;
  }

  Future<Map<String, List<Map<String, dynamic>>>> getCommitsForSelectedRepos({
    required List<Map<String, String>> selectedRepos,
    required List<String> selectedCollaborators,
    required DateTime since,
    required DateTime until,
  }) async {
    final commitsMap = <String, List<Map<String, dynamic>>>{};

    for (final repoInfo in selectedRepos) {
      final owner = repoInfo['owner']!;
      final repo = repoInfo['repo']!;

      for (final collaborator in selectedCollaborators) {
        final queryParameters = {
          'author': collaborator,
          'since': since.toUtc().toIso8601String(),
          'until': until.toUtc().toIso8601String(),
        };

        final uri = Uri.https(
          'api.github.com',
          '/repos/$owner/$repo/commits',
          queryParameters,
        );

        try {
          final response = await http.get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          );

          if (response.statusCode == 200) {
            final List<dynamic> commits = json.decode(response.body);
            printInDebug("raw${commits[0]}");
            final parsedCommits = commits.map<Map<String, dynamic>>((commit) {
              return {
                'sha': commit['sha'],
                'message': commit['commit']['message'],
                'author': commit['commit']['author']['name'],
                'date': commit['commit']['author']['date'],
                'url': commit['html_url'],
              };
            }).toList();

            commitsMap[repo] = [...(commitsMap[repo] ?? []), ...parsedCommits];
          } else {
            throw Exception('Failed to fetch commits for repository $repo');
          }
        } catch (e) {
          printInDebug('Error fetching commits for $repo by $collaborator: $e');
        }
      }
    }
    //printInDebug("commit map$commitsMap");
    return commitsMap;
  }

  Future<Map<String, dynamic>> getCommitDetails({
    required String owner,
    required String repo,
    required String ref,
  }) async {
    final url = 'https://api.github.com/repos/Harsh-Vipin/$repo/commits/$ref';

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final commitDetails = json.decode(response.body);

        return commitDetails;
      } else {
        throw Exception('Failed to fetch commit details: ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
