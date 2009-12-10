# Copyright (c) 2008 ToI-Planning, All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# $Id$

package PreloadTemplate;
use strict;

sub init_pre_run {
	my ($cb, $app) = @_;

	&_preload;
}

sub _preload {
	my $app = MT->instance;

	return 1 if $app->request('preloaded_params');

	require MT::Template;
	my @tmpls = MT::Template->load({
		'blog_id' => ($app->blog ? [0, $app->blog->id] : 0),
		'type' => 'preload',
	});
	my $all_param = {};
	foreach my $tmpl (@tmpls) {
		next unless $tmpl;
		MT->log($tmpl->output);
		my $param = $tmpl->param;
		foreach my $k (keys(%$param)) {
			$all_param->{$k} = $param->{$k};
		}
	}

	$app->request('preloaded_params', $all_param);

	require MT::Template;
	no warnings 'redefine';

	my $template_build = \&MT::Template::build;
	*MT::Template::build = sub {
		my $tmpl = shift;
		my $ctx = shift || $tmpl->context;

		if ($tmpl->id) {
			my $param = $app->request('preloaded_params');
			foreach my $k (%$param) {
				$ctx->{__stash}{vars}{$k} = $param->{$k};
			}
		}

		$template_build->($tmpl, $ctx, @_);
	};
}

sub post_load_template {
	my ($cb, $obj) = @_;
	my $app = MT->instance;

	&_preload;

	if (
		$app->can('mode')
		&& $app->mode eq 'delete'
		&& $obj->type eq 'preload'
	) {
		$obj->type('custom');
	}

	$obj->param($app->request('preloaded_params'));
}

sub param_list_template {
	my ($cb, $app, $param, $tmpl) = @_;
	my $plugin = MT->component('PreloadTemplate');

	my $tmpl_loop = $param->{'template_type_loop'};

	my $blog_id = $app->param('blog_id') || 0;
	my $terms = { blog_id => $blog_id };
	my $args  = { sort    => 'name' };
	my $hasher = sub {
		my ( $obj, $row ) = @_;
		my $template_type;
		my $type = $row->{type} || '';
		my $tblog = MT::Blog->load( $obj->blog_id ) if $obj->blog_id;
		$template_type = 'preload';
		$row->{use_cache} = ( $tblog && $tblog->include_cache && ($obj->cache_expire_type || 0) != 0 )  ? 1 : 0;
		$row->{use_ssi} = ( $tblog && $tblog->include_system && $obj->include_with_ssi )  ? 1 : 0;
		$row->{template_type} = $template_type;
		$row->{type} = 'entry' if $type eq 'individual';
		my $published_url = $obj->published_url;
		$row->{published_url} = $published_url if $published_url;
	};

	my $tmpl_type = 'preload';
	$app->param('filter_key', 'preload_templates');
	my $tmpl_param = {};
	$terms->{type} = 'preload';
	$tmpl_param = $app->listing(
		{
			type     => 'template',
			terms    => $terms,
			args     => $args,
			no_limit => 1,
			no_html  => 1,
			code     => $hasher,
		}
	);
	$tmpl_param->{template_type} = $tmpl_type;
	$tmpl_param->{template_type_label} = $plugin->translate("Preload Templates");
	push @$tmpl_loop, $tmpl_param;


	my $quickfilters = $tmpl->getElementById('quickfilters');
	$quickfilters->innerHTML($quickfilters->innerHTML . <<__EOF__);
<ul>
<li id="preload-tab" class="first-child last-child">
<a class="first-child last-child" onclick="showTable('preload-listing');" href="#preload">@{[ $plugin->translate('Preload Templates') ]}</a>
</li>
</ul>
__EOF__
}

sub __getElementsByTagName {
	my $tmpl = shift;
	my ($name) = @_;
	my $tokens = $tmpl->tokens;
	foreach my $t (@$tokens) {
		if (ref $t && ref $t->attributes && lc ($t->getAttribute('name')) eq 'listing_header') {
			return $t;
		}
	}

	();
}

sub param_template_table {
	my ($cb, $app, $param, $tmpl) = @_;
	my $plugin = MT->component('PreloadTemplate');
	my $append = $plugin->load_tmpl('template_table.tmpl');

	my $lh_orig = (&__getElementsByTagName($tmpl, 'listing_header'))[0];
	my $lh_append = (&__getElementsByTagName($append, 'listing_header'))[0];

	$tmpl->insertAfter($lh_append, $lh_orig);
}

sub param_edit_template {
	my ($cb, $app, $param, $tmpl) = @_;
	my $plugin = MT->component('PreloadTemplate');

	my $type = $param->{'type'};
	if (my $id = $app->param('id')) {
		if (my $tmpl = MT->model('template')->load($id)) {
			$type = $tmpl->type;
		}
	}

	return if $type ne 'preload' && $app->param('subtype') ne 'preload';

	$param->{'type'} = 'preload';

	my $links = $tmpl->getElementById('useful-links');
	$links->innerHTML(<<__EOH__);
            <li><a href="<mt:var name="script_url">?__mode=list_template&amp;blog_id=<mt:var name="blog_id">#preload" class="icon-left icon-related"><__trans phrase="List [_1] templates" params="@{[ $plugin->translate('Preload') ]}"></a></li>
            <li><a href="<mt:var name="script_url">?__mode=list_template&amp;blog_id=<mt:var name="blog_id">" class="icon-left icon-related"><__trans phrase="List all templates"></a></li>
__EOH__
}

sub _hdlr_define_tag {
	my ($ctx, $args, $cond) = @_;

	my $name = $args->{'name'}
		or return $ctx->error("No name");
	my $tokens = $ctx->stash('tokens');

	$ctx->{__handlers}{lc($name)} = sub {
		my ($ctx, $args, $cond) = @_;
        local $ctx->{__stash}{tokens} = $tokens;
		$ctx->slurp($ctx, $args);
	};
}

1;