/**
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the GNU GPLv3 license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dubregistry.repositories.repository;

import vibe.vibe;

import dubregistry.cache;
import dubregistry.dbcontroller : DbRepository, DbRepoStats;
import std.digest.sha;
import std.typecons;


Repository getRepository(DbRepository repinfo)
{
	if( auto pr = repinfo in s_repositories )
		return *pr;

	logDebug("Returning new repository: %s", repinfo);
	auto pf = repinfo.kind in s_repositoryFactories;
	enforce(pf, "Unknown repository type: "~repinfo.kind);
	auto rep = (*pf)(repinfo);
	s_repositories[repinfo] = rep;
	return rep;
}

void addRepositoryFactory(string kind, RepositoryFactory factory)
{
	assert(kind !in s_repositoryFactories);
	s_repositoryFactories[kind] = factory;
}

bool supportsRepositoryKind(string kind)
{
	return (kind in s_repositoryFactories) !is null;
}


alias RepositoryFactory = Repository delegate(DbRepository);

interface Repository {
	RefInfo[] getTags();
	RefInfo[] getBranches();
	/// Get basic repository information, throws FileNotFoundException when the repo no longer exists.
	RepositoryInfo getInfo();
	void readFile(string commit_sha, Path path, scope void delegate(scope InputStream) reader);
	string getDownloadUrl(string tag_or_branch);
	void download(string tag_or_branch, scope void delegate(scope InputStream) del);
}

struct RepositoryInfo {
	bool isFork;
	DbRepoStats stats;
}

struct RefInfo {
	string name;
	string sha;
	BsonDate date;

	this(string name, string sha, SysTime date)
	{
		this.name = name;
		this.sha = sha;
		this.date = BsonDate(date);
	}
}

package Json readJson(string url, bool sanitize = false, bool cache_priority = false)
{
	import dubregistry.internal.utils : black;

	Json ret;
	logDiagnostic("Getting JSON response from %s", url.black);
	Exception ex;
	foreach (i; 0 .. 2) {
		try {
			downloadCached(url, (scope input){
				scope (failure) clearCacheEntry(url);
				auto text = input.readAllUTF8(sanitize);
				ret = parseJsonString(text);
			}, cache_priority);
			return ret;
		} catch (FileNotFoundException e) {
			throw e;
		} catch (Exception e) {
			logDiagnostic("Failed to parse downloaded JSON document (attempt #%s): %s", i+1, e.msg);
			ex = e;
		}
	}
	throw new Exception(format("Failed to read JSON from %s: %s", url.black, ex.msg), __FILE__, __LINE__, ex);
}

private {
	Repository[DbRepository] s_repositories;
	RepositoryFactory[string] s_repositoryFactories;
}
