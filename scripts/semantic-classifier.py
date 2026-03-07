#!/usr/bin/env python3
"""
Semantic Task Classifier for Prompt Optimizer v2.0
Uses TF-IDF + cosine similarity to classify user requests into task categories.
Falls back gracefully if dependencies are missing.

Usage: python3 semantic-classifier.py "user request text"
Returns: category name on stdout
"""

import sys
import math
import re
from collections import Counter

# Category definitions with representative phrases (training corpus)
CATEGORY_CORPUS = {
    "code_implementation": [
        "implement a function", "create a new feature", "build a component",
        "write code for", "add a new endpoint", "develop a module",
        "create a class", "implement the logic", "build a service",
        "add functionality", "write a script", "code a solution",
        "make a function that", "create an app", "build a tool",
        "implement authentication", "add a button", "write a handler",
        "create a new page", "build a form", "implement CRUD operations",
        "add a new route", "develop an API", "write a utility function"
    ],
    "debugging": [
        "fix the bug", "debug this error", "why is this failing",
        "getting an exception", "not working as expected", "crashes when",
        "error message", "stack trace", "fix the issue",
        "broken functionality", "unexpected behavior", "throws an error",
        "null pointer", "undefined is not", "type error",
        "fix the failing test", "resolve this crash", "debug why",
        "stops responding", "memory leak", "infinite loop",
        "race condition", "fix the regression", "troubleshoot"
    ],
    "refactoring": [
        "refactor this code", "clean up the implementation", "restructure",
        "simplify this function", "extract a method", "reduce complexity",
        "improve code quality", "reorganize the module", "decouple",
        "reduce duplication", "apply design pattern", "make it cleaner",
        "split this into smaller functions", "remove dead code",
        "improve readability", "technical debt", "modernize the code",
        "consolidate duplicate logic", "extract interface"
    ],
    "code_review": [
        "review this code", "check this pull request", "look at my changes",
        "review the PR", "code review", "give feedback on this code",
        "check for issues", "review my implementation", "evaluate this approach",
        "is this code correct", "any problems with this", "peer review"
    ],
    "system_design": [
        "design a system", "architect a solution", "system architecture",
        "design a microservice", "distributed system", "scalable architecture",
        "design the database schema", "high level design", "system design",
        "design patterns for", "architect the platform", "design for scale",
        "service oriented architecture", "event driven design",
        "design a data pipeline", "architect a real-time system"
    ],
    "testing": [
        "write tests", "add unit tests", "create test cases",
        "test coverage", "integration tests", "end to end tests",
        "write a test for", "add test coverage", "mock this dependency",
        "test the function", "create a test suite", "add e2e tests",
        "write spec", "test driven development", "add assertions",
        "test the API endpoint", "write a fixture", "snapshot test"
    ],
    "api_integration": [
        "integrate with API", "connect to service", "call the endpoint",
        "REST API", "GraphQL query", "webhook handler",
        "fetch data from", "API authentication", "OAuth integration",
        "consume the API", "third party integration", "API client",
        "connect to database", "integrate payment", "integrate with Stripe",
        "send a request to", "API wrapper", "SDK integration"
    ],
    "frontend": [
        "build a UI component", "create a page", "design the layout",
        "responsive design", "CSS styling", "add animation",
        "create a dashboard", "build a form", "add a modal",
        "frontend component", "user interface", "create a chart",
        "build a navigation", "add a sidebar", "create a table view",
        "design a landing page", "build a visualization", "add dark mode",
        "create a dropdown", "build a carousel", "accessibility"
    ],
    "performance_optimization": [
        "optimize performance", "make it faster", "reduce load time",
        "improve speed", "optimize the query", "reduce memory usage",
        "performance bottleneck", "profiling", "benchmark",
        "cache optimization", "lazy loading", "optimize bundle size",
        "reduce latency", "improve throughput", "optimize rendering",
        "speed up the build", "reduce database queries"
    ],
    "documentation": [
        "write documentation", "create a README", "document the API",
        "add JSDoc comments", "write a guide", "create a tutorial",
        "explain how this works", "document the architecture",
        "add inline comments", "write a changelog", "API documentation",
        "describe the system", "write usage instructions"
    ],
    "security_audit": [
        "security review", "find vulnerabilities", "check for XSS",
        "SQL injection", "security audit", "penetration test",
        "OWASP compliance", "fix security issue", "authentication vulnerability",
        "authorization bypass", "CSRF protection", "input validation security",
        "secure the endpoint", "encryption", "security best practices"
    ],
    "migration": [
        "migrate from", "upgrade to", "convert from", "port to",
        "migration plan", "database migration", "upgrade the framework",
        "transition from", "move from monolith to microservices",
        "migrate the database", "version upgrade", "legacy migration"
    ],
    "devops": [
        "set up CI/CD", "Docker configuration", "Kubernetes deployment",
        "create a pipeline", "deploy to production", "infrastructure as code",
        "Terraform configuration", "GitHub Actions workflow",
        "monitoring setup", "configure nginx", "set up logging",
        "containerize the app", "deploy to AWS", "helm chart"
    ],
    "database": [
        "database schema", "SQL query", "create a table",
        "optimize the query", "database index", "join tables",
        "database migration", "schema design", "normalize the data",
        "PostgreSQL query", "MongoDB aggregation", "Redis caching",
        "database connection pool", "stored procedure"
    ],
    "data_analysis": [
        "analyze the data", "create a report", "data visualization",
        "statistical analysis", "parse the CSV", "data pipeline",
        "aggregate the metrics", "analyze trends", "data cleaning",
        "pandas dataframe", "generate insights", "data transformation"
    ],
    "research": [
        "research options for", "compare alternatives", "what is the best",
        "evaluate technologies", "investigate approaches", "find out how",
        "explore options", "survey the landscape", "compare frameworks",
        "what are the pros and cons", "recommend a library",
        "how does this work", "look into", "find information about",
        "what should I use for", "best practices for", "how to approach",
        "how could I improve", "what can make this better",
        "how could I optimize my", "what are my options",
        "how should I", "what would you recommend", "advise me on",
        "suggest ways to", "give me ideas for", "help me think about",
        "what is the best way to", "how do I improve", "how can I make"
    ],
    "general": [
        "help me with", "can you", "I need", "please do",
        "how to", "what is", "show me", "tell me about"
    ]
}


def tokenize(text):
    """Simple tokenizer: lowercase, split on non-alpha, remove short tokens."""
    text = text.lower()
    tokens = re.findall(r'[a-z]+', text)
    return [t for t in tokens if len(t) > 1]


def build_idf(corpus_docs):
    """Build IDF from all documents."""
    doc_count = len(corpus_docs)
    df = Counter()
    for doc_tokens in corpus_docs:
        unique_tokens = set(doc_tokens)
        for token in unique_tokens:
            df[token] += 1
    idf = {}
    for token, count in df.items():
        idf[token] = math.log((doc_count + 1) / (count + 1)) + 1
    return idf


def tfidf_vector(tokens, idf):
    """Compute TF-IDF vector for a token list."""
    tf = Counter(tokens)
    total = len(tokens) if tokens else 1
    vector = {}
    for token, count in tf.items():
        tf_val = count / total
        idf_val = idf.get(token, math.log(len(idf) + 1) + 1)
        vector[token] = tf_val * idf_val
    return vector


def cosine_similarity(v1, v2):
    """Cosine similarity between two sparse vectors (dicts)."""
    common = set(v1.keys()) & set(v2.keys())
    dot = sum(v1[k] * v2[k] for k in common)
    mag1 = math.sqrt(sum(v ** 2 for v in v1.values())) if v1 else 0
    mag2 = math.sqrt(sum(v ** 2 for v in v2.values())) if v2 else 0
    if mag1 == 0 or mag2 == 0:
        return 0.0
    return dot / (mag1 * mag2)


def classify(request):
    """Classify a request into a task category using TF-IDF + cosine similarity."""
    # Build corpus: each category's phrases merged into one document
    all_docs = []
    categories = []
    for cat, phrases in CATEGORY_CORPUS.items():
        doc_tokens = []
        for phrase in phrases:
            doc_tokens.extend(tokenize(phrase))
        all_docs.append(doc_tokens)
        categories.append(cat)

    # Add the request as a document for IDF computation
    request_tokens = tokenize(request)
    all_docs_for_idf = all_docs + [request_tokens]

    # Build IDF
    idf = build_idf(all_docs_for_idf)

    # Compute request vector
    request_vec = tfidf_vector(request_tokens, idf)

    # Compute similarity to each category
    best_cat = "general"
    best_score = 0.0
    scores = {}

    for i, cat in enumerate(categories):
        cat_vec = tfidf_vector(all_docs[i], idf)
        sim = cosine_similarity(request_vec, cat_vec)
        scores[cat] = sim
        if sim > best_score:
            best_score = sim
            best_cat = cat

    # Confidence threshold: if best score is too low, fall back to general
    if best_score < 0.05:
        best_cat = "general"

    return best_cat, best_score, scores


def main():
    if len(sys.argv) < 2:
        print("general")
        sys.exit(0)

    request = " ".join(sys.argv[1:])
    category, confidence, all_scores = classify(request)

    # If --verbose flag, print all scores
    if "--verbose" in sys.argv:
        request = " ".join(a for a in sys.argv[1:] if a != "--verbose")
        category, confidence, all_scores = classify(request)
        sorted_scores = sorted(all_scores.items(), key=lambda x: -x[1])
        for cat, score in sorted_scores[:5]:
            print(f"  {cat}: {score:.4f}")
        print(f"RESULT: {category} (confidence: {confidence:.4f})")
    else:
        print(category)


if __name__ == "__main__":
    main()
