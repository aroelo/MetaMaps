package Util;

use strict;
use File::Copy;
use List::Util qw/all/;
use Data::Dumper;

use taxTree;

sub get_metaMap_bin_and_enforce_mainDir
{
	my $metamap_bin = './metamaps';
	unless(-e $metamap_bin)
	{
		die "Please execute me from the main MetaMaps directory";
	}
	return $metamap_bin;
}

sub extractContigLengths
{
	my $fn = shift;
	my %forReturn;

	my $currentContigID;
	open(F, '<', $fn) or die "Cannot open file $fn";
	while(<F>)
	{
		chomp;
		if(substr($_, 0, 1) eq '>')
		{
			$currentContigID = substr($_, 1);	
			$forReturn{$currentContigID} = 0;
		}
		else
		{
			$forReturn{$currentContigID} += length($_);
		}
	}
	close(F);
	
	return \%forReturn;
}

sub extractTaxonID
{
	my $contigID = shift;
	my $fileN = shift;
	my $lineN = shift;
	unless($contigID =~ /kraken:taxid\|(x?\d+)/)
	{
		die "Expect taxon ID in contig identifier - file $fileN - line $lineN";
	}			
	return $1;	
}


sub get_index_hash
{
	my $input_aref = shift;
	my @forReturn;
	for(my $i = 0; $i <= $#{$input_aref}; $i++)
	{
		push(@forReturn, $input_aref->[$i], $i);
	}
	return @forReturn;
}
	
sub copyMetaMapDB
{
	my $source = shift;
	my $target = shift;
	
	my @files_required = ('DB.fa', 'taxonInfo.txt', 'contigNstats_windowSize_1000.txt');
	my @files_optional = ('selfSimilarities.txt');
	
	unless(-d $target)
	{
		mkdir($target) or die "Cannot mkdir $target";
	}
	
	foreach my $f (@files_required)
	{
		my $fP = $source . '/' . $f;
		my $tP = $target . '/' . $f;
		unless(-e $fP)
		{
			die "Source DB directory $source doesn't contain file $f";
		}
		copy($fP, $tP) or die "Couldn't copy $fP -> $tP"; 
	}	
	
	foreach my $f (@files_optional)
	{
		my $fP = $source . '/' . $f;
		my $tP = $target . '/' . $f;
		if(-e $fP)
		{
			copy($fP, $tP) or die "Couldn't copy $fP -> $tP"; 
		}
	}	 
	
	copyMetaMapTaxonomy($source . '/taxonomy/', $target . '/taxonomy/');
}

sub copyMetaMapTaxonomy
{
	my $source = shift;
	my $target = shift;
	
	my @existing_files_taxonomy = glob($source . '/*');
	
	my @required_files_taxonomy = taxTree::getTaxonomyFileNames();
	
	die Dumper("Taxonomy files missing?", \@existing_files_taxonomy, @required_files_taxonomy) unless(all {my $requiredFile = $_; my $isThere = (scalar(grep {my $existingFile = $_; my $pattern = '/' . $requiredFile . '$'; my $isMatch = ($existingFile =~ /$pattern/); print join("\t", "'" . $existingFile . "'", "'" . $pattern . "'", $isMatch), "\n" if(1==0); $isMatch} @existing_files_taxonomy) == 1); warn "File $requiredFile missing" unless($isThere); $isThere} @required_files_taxonomy);
	
	$target .= '/';
	unless(-d $target)
	{
		mkdir($target) or die "Cannot mkdir $target";
	}
	foreach my $f (@existing_files_taxonomy)
	{
		copy($f, $target) or die "Cannot copy $f into ${target}";
	}	
}

sub getGenomeLength
{
	my $taxonID = shift;
	my $taxon_2_contig = shift;
	my $contig_2_length = shift;
	
	die unless(defined $contig_2_length);
	
	my $gL = 0;
	die "Cannot determine genome length for taxon ID $taxonID" unless(defined $taxon_2_contig->{$taxonID});
	
	my @contigIDs;
	if(ref($taxon_2_contig->{$taxonID}) eq 'ARRAY')
	{
		@contigIDs = @{$taxon_2_contig->{$taxonID}}
	}
	elsif(ref($taxon_2_contig->{$taxonID}) eq 'HASH')
	{
		@contigIDs = keys %{$taxon_2_contig->{$taxonID}}
	}
	else
	{
		die;
	}
	foreach my $contigID (@contigIDs)
	{
		die unless(defined $contig_2_length->{$contigID});
		$gL += $contig_2_length->{$contigID};
	}
	
	return $gL;
}	

sub mean
{
	my $s = 0;
	die Dumper("No arguments passed to Util::mean?", [@_]) unless(scalar(@_));
	foreach my $v (@_)
	{
		$s += $v;
	}
	return ($s / scalar(@_));
}

sub sd
{
	die unless(scalar(@_));
	my $m = mean(@_);
	my $sd_sum = 0;
	foreach my $e (@_)
	{
		$sd_sum += ($m - $e)**2;
	}
	my $sd = sqrt($sd_sum);
	return $sd;
}

sub getReadLengths
{
	my $file = shift;
	my $cutAfterWhiteSpace = shift;
	
	my %forReturn;
	open(F, '<', $file) or die "Cannot open $file";
	while(<F>)
	{
		my $firstLine = $_;
		chomp($firstLine);
		next unless($firstLine);
		die "Invalid format - is file $file FASTQ?" unless(substr($firstLine, 0, 1) eq '@');
		my $readID = substr($firstLine, 1);
		$readID =~ s/\s.+// if($cutAfterWhiteSpace);		
		my $sequence = <F>;
		chomp($sequence);
		my $plus = <F>;
		die unless(substr($plus, 0, 1) eq '+');
		my $qualities = <F>;
		$forReturn{$readID} = length($sequence);
	}	
	close(F);
	return \%forReturn;
}

sub readFASTA
{
	my $file = shift;	
	my $cut_sequence_ID_after_whitespace = shift;
	
	my %R;
	
	open(F, '<', $file) or die "Cannot open $file";
	my $currentSequence;
	while(<F>)
	{		
		my $line = $_;
		chomp($line);
		$line =~ s/[\n\r]//g;
		if(substr($line, 0, 1) eq '>')
		{
			if($cut_sequence_ID_after_whitespace)
			{
				$line =~ s/\s+.+//;
			}
			$currentSequence = substr($line, 1);
			$R{$currentSequence} = '';
		}
		else
		{
			die "Weird input in $file" unless (defined $currentSequence);
			$R{$currentSequence} .= uc($line);
		}
	}	
	close(F);
		
	return \%R;
}

sub read_taxonIDs_and_contigs
{
	my $DB = shift;
	my $taxonID_2_contigs_href = shift;
	my $contigLength_href = shift;
	
	my $file_taxonGenomes = $DB . '/taxonInfo.txt';
	
	open(GENOMEINFO, '<', $file_taxonGenomes) or die "Cannot open $file_taxonGenomes";
	while(<GENOMEINFO>)
	{
		my $line = $_;
		chomp($line);
		next unless($line);
		my @line_fields = split(/ /, $line);
		die Dumper("Weird line", \@line_fields) unless(scalar(@line_fields) == 2);
		my $taxonID = $line_fields[0];
		my $contigs = $line_fields[1];
		die if(exists $taxonID_2_contigs_href->{$taxonID});

		my @components = split(/;/, $contigs);
		foreach my $component (@components)
		{
			my @p = split(/=/, $component);
			die unless(scalar(@p) == 2);
			die if(exists $taxonID_2_contigs_href->{$taxonID}{$p[0]});
			$taxonID_2_contigs_href->{$taxonID}{$p[0]} = $p[1];
			$contigLength_href->{$p[0]} = $p[1];
		}
	}
	close(GENOMEINFO);
}

1;
