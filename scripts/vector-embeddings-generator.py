#!/usr/bin/env python3
"""
Vector Embeddings Generator for Knowledge-Core
Generates semantic embeddings for intelligent context retrieval
Part of Phase 2: Vector Search System
"""

import json
import os
import sys
from pathlib import Path
from typing import List, Dict, Optional
import hashlib

try:
    import numpy as np
    from sentence_transformers import SentenceTransformer
    from sklearn.metrics.pairwise import cosine_similarity
    DEPS_AVAILABLE = True
except ImportError:
    DEPS_AVAILABLE = False
    print("⚠️  ML dependencies not installed. Install with:", file=sys.stderr)
    print("   pip3 install -r ~/.claude/requirements-vector-search.txt", file=sys.stderr)


class VectorEmbeddingsGenerator:
    """Generates and manages vector embeddings for knowledge-core sections"""

    def __init__(self, knowledge_index_path: str, knowledge_core_path: str,
                 embeddings_path: str, model_name: str = "all-MiniLM-L6-v2"):
        """
        Initialize with paths and model

        Args:
            knowledge_index_path: Path to knowledge-index.json
            knowledge_core_path: Path to knowledge-core.md
            embeddings_path: Path to save embeddings.json
            model_name: Sentence transformer model (default: fast, accurate)
        """
        if not DEPS_AVAILABLE:
            raise ImportError("Required ML libraries not installed")

        with open(knowledge_index_path, 'r') as f:
            self.index = json.load(f)

        with open(knowledge_core_path, 'r') as f:
            self.knowledge_lines = f.readlines()

        self.embeddings_path = embeddings_path

        # Load lightweight, fast model (80MB, runs on CPU)
        print(f"Loading embedding model: {model_name}...")
        self.model = SentenceTransformer(model_name)
        print(f"✅ Model loaded successfully")

    def chunk_section(self, section_text: str, chunk_size: int = 500,
                      overlap: int = 50) -> List[Dict]:
        """
        Split section into overlapping chunks for better retrieval

        Args:
            section_text: Full section text
            chunk_size: Target chunk size in characters
            overlap: Overlap between chunks

        Returns:
            List of chunk dictionaries with text and metadata
        """
        chunks = []
        lines = section_text.split('\n')

        current_chunk = []
        current_size = 0

        for line in lines:
            line_size = len(line)

            if current_size + line_size > chunk_size and current_chunk:
                # Save current chunk
                chunk_text = '\n'.join(current_chunk)
                chunks.append({
                    'text': chunk_text,
                    'size': len(chunk_text),
                    'lines': len(current_chunk)
                })

                # Start new chunk with overlap
                overlap_lines = current_chunk[-3:] if len(current_chunk) > 3 else current_chunk
                current_chunk = overlap_lines + [line]
                current_size = sum(len(l) for l in current_chunk)
            else:
                current_chunk.append(line)
                current_size += line_size

        # Add final chunk
        if current_chunk:
            chunk_text = '\n'.join(current_chunk)
            chunks.append({
                'text': chunk_text,
                'size': len(chunk_text),
                'lines': len(current_chunk)
            })

        return chunks

    def generate_embeddings(self, sections_to_embed: Optional[List[str]] = None) -> Dict:
        """
        Generate embeddings for all sections or specific sections

        Args:
            sections_to_embed: Optional list of section names to embed

        Returns:
            Dictionary with embeddings and metadata
        """
        embeddings_data = {
            'version': '1.0',
            'model': self.model.get_sentence_embedding_dimension(),
            'model_name': str(self.model),
            'sections': {}
        }

        # Get all sections from index
        sections = self.index.get('sections', {})

        total_chunks = 0
        for section_name, section_info in sections.items():
            if sections_to_embed and section_name not in sections_to_embed:
                continue

            print(f"\nProcessing section: {section_name}")

            # Extract section text
            start_line = section_info.get('start_line', 0)
            end_line = section_info.get('end_line', len(self.knowledge_lines))
            section_text = ''.join(self.knowledge_lines[start_line:end_line])

            # Chunk the section
            chunks = self.chunk_section(section_text)
            print(f"  Split into {len(chunks)} chunks")

            # Generate embeddings for each chunk
            chunk_embeddings = []
            for i, chunk in enumerate(chunks):
                embedding = self.model.encode(chunk['text'])
                chunk_embeddings.append({
                    'chunk_id': i,
                    'text': chunk['text'][:200] + '...' if len(chunk['text']) > 200 else chunk['text'],
                    'text_hash': hashlib.md5(chunk['text'].encode()).hexdigest(),
                    'embedding': embedding.tolist(),
                    'size': chunk['size']
                })
                total_chunks += 1

            embeddings_data['sections'][section_name] = {
                'start_line': start_line,
                'end_line': end_line,
                'chunks': chunk_embeddings,
                'total_size': len(section_text)
            }

        print(f"\n✅ Generated {total_chunks} embeddings across {len(embeddings_data['sections'])} sections")
        return embeddings_data

    def save_embeddings(self, embeddings_data: Dict):
        """Save embeddings to JSON file"""
        with open(self.embeddings_path, 'w') as f:
            json.dump(embeddings_data, f, indent=2)

        file_size = Path(self.embeddings_path).stat().st_size / 1024 / 1024
        print(f"✅ Saved embeddings to {self.embeddings_path} ({file_size:.2f} MB)")

    def build(self, sections_to_embed: Optional[List[str]] = None):
        """Build and save embeddings (convenience method)"""
        print("🚀 Building vector embeddings for knowledge-core...")
        embeddings_data = self.generate_embeddings(sections_to_embed)
        self.save_embeddings(embeddings_data)
        print("✅ Vector embeddings build complete!")


class VectorSearchEngine:
    """Semantic search engine using vector embeddings"""

    def __init__(self, embeddings_path: str, model_name: str = "all-MiniLM-L6-v2"):
        """
        Initialize search engine

        Args:
            embeddings_path: Path to embeddings.json
            model_name: Sentence transformer model (must match generator)
        """
        if not DEPS_AVAILABLE:
            raise ImportError("Required ML libraries not installed")

        with open(embeddings_path, 'r') as f:
            self.embeddings_data = json.load(f)

        # Load same model as generator
        self.model = SentenceTransformer(model_name)

        # Build lookup structures
        self._build_search_index()

    def _build_search_index(self):
        """Build fast lookup structures"""
        self.chunk_index = []
        self.embeddings_matrix = []

        for section_name, section_data in self.embeddings_data['sections'].items():
            for chunk in section_data['chunks']:
                self.chunk_index.append({
                    'section': section_name,
                    'chunk_id': chunk['chunk_id'],
                    'text': chunk['text'],
                    'start_line': section_data['start_line'],
                    'end_line': section_data['end_line']
                })
                self.embeddings_matrix.append(chunk['embedding'])

        self.embeddings_matrix = np.array(self.embeddings_matrix)
        print(f"✅ Search index built: {len(self.chunk_index)} chunks ready")

    def search(self, query: str, top_k: int = 5, min_similarity: float = 0.3) -> List[Dict]:
        """
        Semantic search for most relevant chunks

        Args:
            query: User query text
            top_k: Number of results to return
            min_similarity: Minimum cosine similarity threshold

        Returns:
            List of results with sections, scores, and text
        """
        # Generate query embedding
        query_embedding = self.model.encode(query).reshape(1, -1)

        # Calculate cosine similarities
        similarities = cosine_similarity(query_embedding, self.embeddings_matrix)[0]

        # Get top-k indices
        top_indices = np.argsort(similarities)[::-1][:top_k]

        # Build results
        results = []
        for idx in top_indices:
            score = float(similarities[idx])
            if score < min_similarity:
                continue

            chunk_info = self.chunk_index[idx]
            results.append({
                'section': chunk_info['section'],
                'chunk_id': chunk_info['chunk_id'],
                'text_preview': chunk_info['text'],
                'similarity_score': score,
                'start_line': chunk_info['start_line'],
                'end_line': chunk_info['end_line']
            })

        return results

    def get_relevant_sections(self, query: str, top_k: int = 5) -> Dict:
        """
        Get unique sections from search results

        Args:
            query: User query
            top_k: Number of chunks to consider

        Returns:
            Dictionary with sections and confidence scores
        """
        search_results = self.search(query, top_k=top_k)

        # Aggregate by section
        section_scores = {}
        for result in search_results:
            section = result['section']
            score = result['similarity_score']

            if section not in section_scores:
                section_scores[section] = {
                    'max_score': score,
                    'avg_score': score,
                    'chunk_count': 1,
                    'chunks': [result]
                }
            else:
                section_scores[section]['max_score'] = max(section_scores[section]['max_score'], score)
                section_scores[section]['avg_score'] = (
                    (section_scores[section]['avg_score'] * section_scores[section]['chunk_count'] + score) /
                    (section_scores[section]['chunk_count'] + 1)
                )
                section_scores[section]['chunk_count'] += 1
                section_scores[section]['chunks'].append(result)

        # Sort by max score
        sorted_sections = sorted(
            section_scores.items(),
            key=lambda x: x[1]['max_score'],
            reverse=True
        )

        return {
            'query': query,
            'sections_found': len(sorted_sections),
            'sections': {name: data for name, data in sorted_sections}
        }


def main():
    """CLI interface for vector embeddings system"""
    import argparse

    parser = argparse.ArgumentParser(description='Vector Embeddings Generator for Knowledge-Core')
    parser.add_argument('command', choices=['build', 'search', 'test'],
                        help='Command to execute')
    parser.add_argument('--query', type=str, help='Query for search command')
    parser.add_argument('--sections', type=str, nargs='*', help='Sections to embed (default: all)')
    parser.add_argument('--top-k', type=int, default=5, help='Number of results (default: 5)')
    parser.add_argument('--model', type=str, default='all-MiniLM-L6-v2',
                        help='Sentence transformer model')

    args = parser.parse_args()

    # Paths
    claude_dir = Path.home() / '.claude'
    knowledge_index = claude_dir / 'knowledge-index.json'
    knowledge_core = claude_dir / 'knowledge-core.md'
    embeddings_file = claude_dir / 'data' / 'knowledge-embeddings.json'

    if args.command == 'build':
        generator = VectorEmbeddingsGenerator(
            str(knowledge_index),
            str(knowledge_core),
            str(embeddings_file),
            model_name=args.model
        )
        generator.build(sections_to_embed=args.sections)

    elif args.command == 'search':
        if not args.query:
            print("Error: --query required for search command", file=sys.stderr)
            sys.exit(1)

        engine = VectorSearchEngine(str(embeddings_file), model_name=args.model)
        results = engine.get_relevant_sections(args.query, top_k=args.top_k)

        print(json.dumps(results, indent=2))

    elif args.command == 'test':
        # Test queries
        test_queries = [
            "How do I configure /review command for security?",
            "Calculate ROI for 30 developers",
            "Install Qodo Gen in VS Code",
            "Prepare demo for TechCo"
        ]

        engine = VectorSearchEngine(str(embeddings_file), model_name=args.model)

        for query in test_queries:
            print(f"\n{'='*80}")
            print(f"Query: {query}")
            print(f"{'='*80}")

            results = engine.get_relevant_sections(query, top_k=3)
            print(f"Found {results['sections_found']} relevant sections:")

            for section_name, section_data in results['sections'].items():
                print(f"\n  📍 {section_name}")
                print(f"     Score: {section_data['max_score']:.3f}")
                print(f"     Chunks: {section_data['chunk_count']}")


if __name__ == '__main__':
    if not DEPS_AVAILABLE:
        print("\n⚠️  Please install required dependencies first:", file=sys.stderr)
        print("   pip3 install -r ~/.claude/requirements-vector-search.txt\n", file=sys.stderr)
        sys.exit(1)

    main()
