// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: "https://unityjaeger.github.io",
	base: "/Scrivener",
	integrations: [
		starlight({
			title: 'Scrivener',
			tableOfContents: {minHeadingLevel: 2, maxHeadingLevel: 4},
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/unityjaeger/Scrivener' }],
			sidebar: [
				{
					label: 'Guides',
					items: [
						// Each item here is one entry in the navigation menu.
						{ label: 'Intro', slug: 'guides/intro' },
						{ label: 'Usage', slug: 'guides/usage' },
						{ label: 'Examples', slug: 'guides/examples' },
						{ label: 'Custom Types', slug: 'guides/custom_types' }
					],
				}
			],
		}),
	],
});