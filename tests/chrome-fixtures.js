#!/usr/bin/env node
/* Offline DOM fixtures for the production helper block. No browser or package. */
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(0, 'utf8');

class Style {
  constructor(values = {}) { this.values = {...values}; this.priority = {}; }
  getPropertyValue(k) { return this.values[k] || ''; }
  getPropertyPriority(k) { return this.priority[k] || ''; }
  setProperty(k, v, p = '') { this.values[k] = String(v); this.priority[k] = p; }
  removeProperty(k) { delete this.values[k]; delete this.priority[k]; }
  get display() { return this.values.display || ''; }
  set display(v) { this.values.display = v; }
}
class Element {
  constructor(tag, attrs = {}, rect = [0, 0, 0, 0], style = {}) {
    this.tagName = tag.toUpperCase(); this.attrs = {...attrs}; this.rect = rect;
    this.style = new Style(style); this.children = []; this.parentElement = null;
    this.dataset = {}; this.textContent = attrs.text || '';
  }
  append(...children) { for (const child of children) { child.parentElement = this; this.children.push(child); } return this; }
  getBoundingClientRect() { const [x, y, width, height] = this.rect; return {x, y, width, height, left: x, top: y, right: x + width, bottom: y + height}; }
  getAttribute(k) { return this.attrs[k] || ''; }
  contains(node) { for (let n = node; n; n = n.parentElement) if (n === this) return true; return false; }
  matches(selector) {
    return selector.split(',').some(raw => {
      const s = raw.trim();
      if (!s || s.includes(' ') || s.includes('>')) return false;
      const tag = s.match(/^[a-z*]+/i);
      if (tag && tag[0] !== '*' && tag[0].toUpperCase() !== this.tagName) return false;
      const id = s.match(/#([\w-]+)/);
      if (id && id[1] !== (this.attrs.id || '')) return false;
      for (const cls of s.matchAll(/\.([\w-]+)/g))
        if (!(this.attrs.class || '').split(/\s+/).includes(cls[1])) return false;
      for (const attr of s.matchAll(/\[([\w-]+)(?:([~|^$*]?=)["']?([^\]"']*)["']?)?\]/g)) {
        const value = this.attrs[attr[1]] || '';
        if (!attr[2] ? !(attr[1] in this.attrs) : attr[2] === '=' && value !== attr[3]) return false;
      }
      return true;
    });
  }
  closest(selector) {
    for (let node = this; node; node = node.parentElement) if (node.matches(selector)) return node;
    return null;
  }
  querySelectorAll(selector) {
    const result = [];
    const visit = node => {
      for (const child of node.children) {
        if (child.matches(selector)) result.push(child);
        visit(child);
      }
    };
    visit(this); return result;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
const body = new Element('body', {}, [0, 0, 1000, 800]);
const header = new Element('header', {id: 'gb', role: 'banner'}, [0, 0, 617, 64]);
const ask = new Element('button', {'aria-label': 'Ask Gemini'}, [500, 8, 40, 40]);
const icon = new Element('div', {class: 'MxSLJe'}, [560, 8, 40, 40]);
const nestedButton = new Element('button', {}, [430, 8, 40, 40]);
const nestedIcon = new Element('span', {class: 'Pv5YRd'}, [430, 8, 40, 40]);
nestedButton.append(nestedIcon);
// A release-shaped launcher: the named button and decorative SVG are siblings
// inside the small visual wrapper, which itself sits in a broad header cluster.
const launcherCluster = new Element('div', {class: 'header-cluster'}, [480, 0, 137, 64]);
const launcherWrapper = new Element('div', {class: 'launcher-wrapper'}, [500, 8, 40, 40]);
const launcherSpan = new Element('span', {}, [500, 8, 40, 40]);
const launcherButton = new Element('button', {'aria-label': 'Ask Gemini'}, [500, 8, 40, 40]);
const launcherSvg = new Element('svg', {viewBox: '0 0 960 960'}, [500, 8, 40, 40]);
launcherSvg.append(new Element('path', {d: 'M480-80q-6-6-6-14'}, [500, 8, 40, 40]));
launcherSpan.append(launcherButton);
launcherWrapper.append(launcherSpan, new Element('div', {class: 'ekylFf'}, [500, 8, 40, 40]), launcherSvg);
launcherCluster.append(launcherWrapper);
const viewButton = new Element('button', {text: 'Montharrow_drop_down'}, [300, 8, 120, 40]);
const namelessChrome = new Element('button', {}, [580, 8, 30, 40]);
const calendarFilter = new Element('button', {'aria-label': 'Filter and view'}, [270, 8, 24, 40]);
header.append(ask, nestedButton, icon, launcherCluster, calendarFilter, viewButton, namelessChrome);
const message = new Element('div', {text: 'An email mentioning Gemini must remain content.'}, [10, 100, 400, 100]);
body.append(header, message);
const menu = new Element('ul', {role: 'menu'}, [100, 140, 200, 160]);
menu.append(new Element('li', {role: 'menuitem', text: 'Day'}, [100, 140, 200, 40]));
menu.append(new Element('li', {role: 'menuitem', text: 'Week'}, [100, 180, 200, 40]));
menu.append(new Element('li', {role: 'menuitem', text: 'Month'}, [100, 220, 200, 40]));
const zeroMenu = new Element('ul', {role: 'menu', text: 'Month Week'}, [0, 0, 0, 0]);
zeroMenu.append(new Element('li', {role: 'menuitem', text: 'Day'}, [0, 0, 0, 0]));
zeroMenu.append(new Element('li', {role: 'menuitem', text: 'Week'}, [0, 0, 0, 0]));
zeroMenu.append(new Element('li', {role: 'menuitem', text: 'Month'}, [0, 0, 0, 0]));
// An adversarial menu with real-sized choices but no viewport intersection must
// remain invalid; the verification probe is not allowed to move or restyle it.
const offscreenMenu = new Element('ul', {role: 'menu'}, [100, 900, 200, 160]);
offscreenMenu.append(new Element('li', {role: 'menuitem', text: 'Day'}, [100, 900, 200, 40]));
offscreenMenu.append(new Element('li', {role: 'menuitem', text: 'Week'}, [100, 940, 200, 40]));
offscreenMenu.append(new Element('li', {role: 'menuitem', text: 'Month'}, [100, 980, 200, 40]));
body.append(menu, zeroMenu, offscreenMenu);
const hidden = node => {
  for (let n = node; n; n = n.parentElement) {
    if (n.style.display === 'none' || n.style.values.visibility === 'hidden') return true;
  }
  return false;
};
const all = node => [node, ...node.children.flatMap(all)];
const fakeDocument = {
  body,
  documentElement: body,
  querySelector: selector => selector === '#gb, header[role="banner"]' ? header :
    selector === '[aria-label="Filter and view"]' ? calendarFilter : null,
  elementFromPoint: (x, y) => all(body).reverse().find(el => {
    const r = el.getBoundingClientRect();
    return !hidden(el) && r.width > 0 && r.height > 0 && x >= r.left && x < r.right && y >= r.top && y < r.bottom;
  }) || null,
  addEventListener: () => {},
};
const context = {
  window: {innerWidth: 1000, innerHeight: 800}, document: fakeDocument,
  getComputedStyle: el => ({display: el.style.display || 'block', visibility: el.style.values.visibility || 'visible', opacity: el.style.values.opacity || '1'}),
  console
};
vm.runInNewContext(source, context);
const h = context.window.__gcalChromeHelpers;
function check(ok, message) { if (!ok) throw new Error(message); }

// Header scoping excludes message text and promotes a nested icon to its button.
check(h.scopedGeminiCandidates().includes(ask), 'named header launcher not identified');
check(!h.scopedGeminiCandidates().includes(message), 'message content was treated as a launcher');
check(h.scopedGeminiCandidates().includes(icon), 'icon-only scoped launcher not identified');
check(h.scopedGeminiCandidates().includes(nestedButton), 'nested icon did not select its button');
const promoted = h.scopedGeminiCandidates();
check(promoted.includes(launcherWrapper), 'decorative Gemini wrapper was not promoted');
check(!promoted.includes(launcherButton), 'wrapper promotion left only the nested button selected');
check(!promoted.includes(launcherCluster), 'promotion crossed into the broad header cluster');
// Production hides the returned targets, not merely the nested control. This
// also exercises the marked-zero-size path used by later mutation passes.
for (const target of promoted) {
  target.dataset.suiteHidden = '1';
  target.style.setProperty('display', 'none', 'important');
}
check(hidden(launcherWrapper), 'production candidate set did not hide the wrapper');
check(launcherWrapper.dataset.suiteHidden === '1', 'wrapper was not marked hidden');
check(!hidden(message), 'hiding launchers touched message content');
// The positional rule has one narrow exception: the actual unnamed #gb
// Montharrow_drop_down button. Arbitrary nameless chrome and the separate
// Filter and view icon are not substitutes.
check(h.calendarViewButton(viewButton), 'real Montharrow_drop_down button was not identified');
check(!h.calendarViewButton(namelessChrome), 'nameless chrome was incorrectly preserved');
check(!h.calendarViewButton(calendarFilter), 'Filter icon stood in for the real dropdown');
// Real menu geometry is required; text alone never makes a menu or choice valid.
check(h.menuVisible(menu), 'real menu did not pass geometry/hit testing');
check(h.calendarChoicesValid(h.menuChoices(menu)), 'real Month/Week choices did not pass');
check(!h.menuVisible(zeroMenu), 'zero-sized adversarial menu passed');
check(h.menuChoices(zeroMenu).length === 0, 'zero-sized Month/Week nodes passed');
check(!h.menuVisible(offscreenMenu), 'offscreen adversarial menu passed');
check(h.menuChoices(offscreenMenu).length === 0, 'offscreen Month/Week nodes passed');
check(!h.calendarChoicesValid(['Filter and view']), 'button label falsely passed menu verification');
check(h.calendarChoicesValid(['Day', 'Week', 'Month', 'Schedule']), 'real Calendar choices did not pass');
check(h.menuChoices(menu).includes('Day') && h.menuChoices(menu).includes('Week')
  && h.menuChoices(menu).includes('Month'), 'visible Calendar menu choices were not collected');
// Google retains the same sized menu node off-screen after close. Interactive
// state must make that node eligible again on every later opening.
let repeatedCycleEligible = true;
for (let cycle = 0; cycle < 2; cycle++) {
  const wasInteractive = h.menuVisible(offscreenMenu);
  offscreenMenu.rect = [100, 140, 200, 160];
  repeatedCycleEligible &&= !wasInteractive && h.menuVisible(offscreenMenu);
  offscreenMenu.rect = [100, 900, 200, 160];
}
check(repeatedCycleEligible, 'retained off-screen menu failed on the second open cycle');
console.log('CHROME_FIXTURES ok (23 checks)');
